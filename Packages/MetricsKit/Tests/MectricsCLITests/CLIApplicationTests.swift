import Foundation
@testable import MectricsCLICore
import MetricsKit
import XCTest

private final class OutputCapture: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var stdout = ""
    private(set) var stderr = ""

    var output: CLIOutput {
        CLIOutput(
            standardOutput: { [weak self] message in
                self?.append(message, toStandardError: false)
            },
            standardError: { [weak self] message in
                self?.append(message, toStandardError: true)
            }
        )
    }

    private func append(_ message: String, toStandardError: Bool) {
        lock.lock()
        defer { lock.unlock() }
        if toStandardError {
            stderr += message
        } else {
            stdout += message
        }
    }
}

private final class SequenceProvider: MetricProvider, @unchecked Sendable {
    let id: MetricID
    let isAvailable: Bool
    let cost: SamplingCost = .light
    private var samples: [MetricSample?]

    init(
        id: MetricID,
        isAvailable: Bool = true,
        samples: [MetricSample?]
    ) {
        self.id = id
        self.isAvailable = isAvailable
        self.samples = samples
    }

    func sample() -> MetricSample? {
        guard !samples.isEmpty else { return nil }
        return samples.removeFirst()
    }
}

private final class RequestedMetricsCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Set<MetricID>?

    func set(_ ids: Set<MetricID>) {
        lock.lock()
        value = ids
        lock.unlock()
    }

    func get() -> Set<MetricID>? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

@MainActor
final class CLIApplicationTests: XCTestCase {
    func testCheckReturnsAttentionAndKeepsJSONOnStandardOutput() async throws {
        let capture = OutputCapture()
        let configuration = AlertConfiguration(
            thresholdRules: [
                .cpu: AlertRule(enabled: true, thresholdPercent: 80)
            ],
            systemRules: [:]
        )
        let application = CLIApplication(
            output: capture.output,
            providerFactory: { _ in
                [SequenceProvider(id: .cpu, samples: [MetricSample(value: 0.9)])]
            },
            loadConfiguration: { configuration },
            version: "test"
        )

        let exitCode = try await application.check(json: true)

        XCTAssertEqual(exitCode, 1)
        XCTAssertTrue(capture.stderr.isEmpty)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(capture.stdout.utf8))
                as? [String: Any]
        )
        XCTAssertEqual(object["status"] as? String, "attention")
    }

    func testThermalOnlyCheckDoesNotConstructAProvider() async throws {
        let capture = OutputCapture()
        let configuration = AlertConfiguration(
            thresholdRules: [:],
            systemRules: [
                .thermalPressure: SystemAlertRule(
                    enabled: true,
                    thresholdValue: 3
                )
            ]
        )
        let requested = RequestedMetricsCapture()
        let application = CLIApplication(
            output: capture.output,
            providerFactory: { ids in
                requested.set(ids)
                return []
            },
            loadConfiguration: { configuration },
            version: "test"
        )

        _ = try await application.check(json: true)

        XCTAssertEqual(requested.get(), [])
    }

    func testUnavailableRuleNeverBecomesHealthy() async throws {
        let capture = OutputCapture()
        let configuration = AlertConfiguration(
            thresholdRules: [
                .battery: AlertRule(enabled: true, thresholdPercent: 20)
            ],
            systemRules: [:]
        )
        let application = CLIApplication(
            output: capture.output,
            providerFactory: { _ in
                [SequenceProvider(id: .battery, isAvailable: false, samples: [])]
            },
            loadConfiguration: { configuration },
            version: "test"
        )

        let exitCode = try await application.check(json: true)

        XCTAssertEqual(exitCode, 2)
        XCTAssertTrue(capture.stdout.contains("\"status\":\"unavailable\""))
    }

    func testDoctorDegradesForABrokenInstalledCommandLink() throws {
        let capture = OutputCapture()
        let configuration = AlertConfiguration(
            thresholdRules: [
                .cpu: AlertRule(enabled: true, thresholdPercent: 80)
            ],
            systemRules: [:]
        )
        let application = CLIApplication(
            output: capture.output,
            providerFactory: { _ in
                [SequenceProvider(id: .cpu, samples: [])]
            },
            loadConfiguration: { configuration },
            version: "test",
            installedCommandState: { .brokenLink }
        )

        let exitCode = try application.doctor(json: true)

        XCTAssertEqual(exitCode, 2)
        XCTAssertTrue(capture.stdout.contains("\"status\":\"degraded\""))
        XCTAssertTrue(capture.stdout.contains("\"installedCommand\":\"brokenLink\""))
    }

    func testWatchDoesNotActivateFromAReadingAfterSamplingFails() async throws {
        let configuration = AlertConfiguration(
            thresholdRules: [
                .cpu: AlertRule(
                    enabled: true,
                    thresholdPercent: 80,
                    durationSeconds: 1,
                    cooldownSeconds: 0
                )
            ],
            systemRules: [:]
        )
        let provider = SequenceProvider(
            id: .cpu,
            samples: [MetricSample(value: 0.95), nil, nil, nil]
        )
        var records: [WatchStreamRecord] = []
        let session = AlertWatchSession(
            configuration: configuration,
            heartbeatInterval: .seconds(60),
            providerFactory: { _ in [provider] },
            staleAfter: 2,
            onLegacyEvent: { _ in },
            onRecord: { records.append($0) },
            onDiagnostic: { _ in }
        )

        try session.start()
        try await Task.sleep(for: .milliseconds(3_300))
        session.stop()

        XCTAssertFalse(records.contains { $0.type == .alert })
        XCTAssertTrue(records.contains {
            $0.type == .status && $0.status == .degraded
        })
    }
}
