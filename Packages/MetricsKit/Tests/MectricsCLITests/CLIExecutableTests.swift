import Foundation
import MetricsKit
import XCTest

final class CLIExecutableTests: XCTestCase {
    func testRealExecutableUsesUsageExitCode() throws {
        let result = try runCLI(["bogus-command"])

        XCTAssertEqual(result.status, 64)
        XCTAssertTrue(result.stdout.isEmpty)
        XCTAssertTrue(result.stderr.contains("Unexpected argument"))
    }

    func testRealExecutableReturnsAttentionForConfiguredNativeRule() throws {
        let domain = "MectricsCLITests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let rules = [
            SystemAlertSignal.thermalPressure.rawValue: SystemAlertRule(
                enabled: true,
                thresholdValue: 0,
                durationSeconds: 0
            )
        ]
        defaults.set(
            try JSONEncoder().encode(rules),
            forKey: AlertConfigurationStorage.systemRulesKey
        )

        let result = try runCLI(
            ["check", "--json"],
            environment: ["MECTRICS_CLI_TEST_PREFERENCES_DOMAIN": domain]
        )

        XCTAssertEqual(result.status, 1)
        XCTAssertTrue(result.stderr.isEmpty)
        XCTAssertTrue(result.stdout.contains("\"status\":\"attention\""))
    }

    func testRealWatchWritesReadyRecordBeforeWaiting() throws {
        let domain = "MectricsCLITests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let rules = [
            SystemAlertSignal.thermalPressure.rawValue: SystemAlertRule(
                enabled: true,
                thresholdValue: 3,
                durationSeconds: 30
            )
        ]
        defaults.set(
            try JSONEncoder().encode(rules),
            forKey: AlertConfigurationStorage.systemRulesKey
        )

        let process = try makeProcess(
            ["alerts", "watch", "--json", "--heartbeat", "5"],
            environment: ["MECTRICS_CLI_TEST_PREFERENCES_DOMAIN": domain]
        )
        try process.process.run()
        Thread.sleep(forTimeInterval: 0.5)
        process.process.terminate()
        process.process.waitUntilExit()
        let stdout = String(
            data: process.standardOutput.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""

        let firstLine = try XCTUnwrap(stdout.split(separator: "\n").first)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(firstLine.utf8))
                as? [String: Any]
        )
        XCTAssertEqual(object["type"] as? String, "ready")
        XCTAssertEqual(object["status"] as? String, "healthy")
    }

    func testRealExecutableProvidesNestedHelp() throws {
        let result = try runCLI(["check", "--help"])

        XCTAssertEqual(result.status, 0)
        XCTAssertTrue(result.stdout.contains("mectrics check [--json]"))
        XCTAssertTrue(result.stderr.isEmpty)
    }

    func testRealExecutableReportsColdConfigurationAsJSON() throws {
        let result = try runCLI(
            ["check", "--json"],
            environment: [
                "MECTRICS_CLI_TEST_PREFERENCES_DOMAIN":
                    "MectricsCLITests.\(UUID().uuidString)"
            ]
        )

        XCTAssertEqual(result.status, 2)
        XCTAssertTrue(result.stderr.isEmpty)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(result.stdout.utf8))
                as? [String: Any]
        )
        XCTAssertEqual(object["status"] as? String, "notConfigured")
    }

    func testRealExecutableRejectsCorruptConfiguration() throws {
        let domain = "MectricsCLITests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set(
            Data("not-json".utf8),
            forKey: AlertConfigurationStorage.thresholdRulesKey
        )

        let result = try runCLI(
            ["check", "--json"],
            environment: ["MECTRICS_CLI_TEST_PREFERENCES_DOMAIN": domain]
        )

        XCTAssertEqual(result.status, 78)
        XCTAssertTrue(result.stdout.isEmpty)
        XCTAssertTrue(result.stderr.contains("could not be read"))
    }

    private func runCLI(
        _ arguments: [String],
        environment additions: [String: String] = [:]
    ) throws -> (status: Int32, stdout: String, stderr: String) {
        let invocation = try makeProcess(arguments, environment: additions)
        try invocation.process.run()
        invocation.process.waitUntilExit()

        return (
            invocation.process.terminationStatus,
            String(
                data: invocation.standardOutput.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? "",
            String(
                data: invocation.standardError.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
        )
    }

    private func makeProcess(
        _ arguments: [String],
        environment additions: [String: String]
    ) throws -> (process: Process, standardOutput: Pipe, standardError: Pipe) {
        let productsDirectory = Bundle(for: Self.self).bundleURL
            .deletingLastPathComponent()
        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.executableURL = productsDirectory.appending(path: "mectrics")
        process.arguments = arguments
        process.standardOutput = standardOutput
        process.standardError = standardError
        process.environment = ProcessInfo.processInfo.environment.merging(additions) {
            _, new in new
        }
        return (process, standardOutput, standardError)
    }
}
