import ArgumentParser
import Foundation
@testable import MectricsCLICore
import MetricsKit
import XCTest

final class CLIContractTests: XCTestCase {
    func testHealthExitCodesRemainStable() {
        XCTAssertEqual(healthExitCode(.healthy), 0)
        XCTAssertEqual(healthExitCode(.attention), 1)
        XCTAssertEqual(healthExitCode(.unavailable), 2)
        XCTAssertEqual(healthExitCode(.notConfigured), 2)
    }

    func testNestedHelpParsesAsCleanExit() {
        let help = MectricsCommand.helpMessage(for: CheckCLICommand.self)
        XCTAssertTrue(help.contains("mectrics check [--json]"))
        XCTAssertTrue(help.contains("--json"))
    }

    func testHeartbeatRequiresJSON() {
        XCTAssertThrowsError(
            try AlertsWatchCLICommand.parse(["--heartbeat", "60"])
        )
    }

    func testTaggedHeartbeatHasStableDiscriminator() throws {
        let timestamp = Date(timeIntervalSince1970: 1_000)
        let coverage = WatchCoverageSnapshot(
            status: .degraded,
            watchedConditions: ["threshold.cpu"],
            unavailableConditions: ["threshold.battery"],
            collectingConditions: [],
            staleMetrics: [.cpu],
            lastSampleAt: timestamp
        )
        let encoded = try CLIJSON.encode(
            WatchStreamRecord.heartbeat(coverage, timestamp: timestamp)
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(encoded.utf8))
                as? [String: Any]
        )

        XCTAssertEqual(object["schemaVersion"] as? Int, 1)
        XCTAssertEqual(object["type"] as? String, "heartbeat")
        XCTAssertEqual(object["status"] as? String, "degraded")
    }

    func testAlertJSONMatchesVersionOneFixture() throws {
        let update = AlertConditionUpdate(
            metricID: .cpu,
            state: .active,
            transition: .activated,
            measuredValue: 90,
            unit: .percent,
            thresholdValue: 80,
            durationSeconds: 30,
            startedAt: Date(timeIntervalSince1970: 1_000),
            destinations: [.attentionLog]
        )
        let event = AlertStreamEvent(
            update: update,
            timestamp: Date(timeIntervalSince1970: 1_030)
        )

        XCTAssertEqual(
            try CLIJSON.encode(event),
            try fixture(named: "alert-v1-activated")
        )
    }

    func testUnavailableCheckJSONMatchesVersionOneFixture() throws {
        let report = AlertHealthReport(
            configuration: AlertConfiguration(
                thresholdRules: [
                    .cpu: AlertRule(enabled: true, thresholdPercent: 80)
                ],
                systemRules: [:]
            ),
            latest: [:],
            timestamp: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(
            try CLIJSON.encode(report),
            try fixture(named: "check-v1-unavailable")
        )
    }

    func testSnapshotJSONMatchesVersionOneFixture() throws {
        let report = MetricSnapshotReport(
            latest: [
                .cpu: MetricSample(
                    timestamp: Date(timeIntervalSince1970: 1_000),
                    value: 0.25,
                    detail: ["coreCount": 8]
                )
            ],
            requested: [.cpu, .battery],
            timestamp: Date(timeIntervalSince1970: 1_030)
        )

        XCTAssertEqual(
            try CLIJSON.encode(report),
            try fixture(named: "snapshot-v1-partial")
        )
    }

    func testConfigurationValidationRejectsUnsafeTiming() {
        let configuration = AlertConfiguration(
            thresholdRules: [
                .cpu: AlertRule(
                    enabled: true,
                    thresholdPercent: 90,
                    durationSeconds: -1
                )
            ],
            systemRules: [:]
        )

        XCTAssertThrowsError(try AlertConfigurationStore.validate(configuration))
    }

    func testJSONEncodingFailureUsesSoftwareExitCode() {
        struct NonFinitePayload: Encodable {
            let value = Double.nan
        }

        XCTAssertThrowsError(try CLIJSON.encode(NonFinitePayload())) { error in
            XCTAssertEqual((error as? CLIExecutionError)?.exitCode, 70)
        }
    }

    private func fixture(named name: String) throws -> String {
        let url = try XCTUnwrap(
            Bundle.module.url(
                forResource: name,
                withExtension: "json",
                subdirectory: "Fixtures"
            )
        )
        return try String(contentsOf: url, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
