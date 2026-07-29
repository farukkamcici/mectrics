import MetricsKit
import XCTest
@testable import Mectrics

final class SystemConditionMonitorTests: XCTestCase {
    func testMemoryPressureSustainsActivatesOnceAndRecovers() {
        var deliveries = 0
        var updates: [AlertConditionUpdate] = []
        let monitor = SystemConditionMonitor { _, _, _ in deliveries += 1 }
        monitor.onConditionUpdate = { updates.append($0) }
        let start = Date(timeIntervalSince1970: 1_000)
        let rule = SystemAlertRule(
            enabled: true,
            thresholdValue: 2,
            durationSeconds: 30,
            destinations: [.notification, .attentionLog]
        )

        evaluate(
            monitor,
            .memoryPressure,
            value: 2,
            rule: rule,
            now: start
        )
        evaluate(
            monitor,
            .memoryPressure,
            value: 4,
            rule: rule,
            now: start.addingTimeInterval(30)
        )
        evaluate(
            monitor,
            .memoryPressure,
            value: 4,
            rule: rule,
            now: start.addingTimeInterval(60)
        )

        XCTAssertEqual(monitor.state(for: .memoryPressure), .active)
        XCTAssertEqual(deliveries, 1)

        evaluate(
            monitor,
            .memoryPressure,
            value: 1,
            rule: rule,
            now: start.addingTimeInterval(61)
        )
        XCTAssertEqual(monitor.state(for: .memoryPressure), .normal)
        XCTAssertEqual(
            updates.map(\.transition),
            [.pending, .activated, .recovered]
        )
        XCTAssertTrue(
            updates.allSatisfy {
                $0.conditionKey
                    == SystemAlertSignal.memoryPressure.conditionKey
            }
        )
    }

    func testDiskCapacityUsesBelowSemanticsAndCooldown() {
        var deliveries = 0
        let monitor = SystemConditionMonitor { _, _, _ in deliveries += 1 }
        let start = Date(timeIntervalSince1970: 2_000)
        let limit = 20.0 * 1_024 * 1_024 * 1_024
        let rule = SystemAlertRule(
            enabled: true,
            thresholdValue: limit,
            durationSeconds: 0,
            cooldownSeconds: 900,
            destinations: [.notification]
        )

        evaluate(
            monitor,
            .diskAvailableCapacity,
            value: limit + 1,
            rule: rule,
            now: start
        )
        XCTAssertEqual(deliveries, 0)

        evaluate(
            monitor,
            .diskAvailableCapacity,
            value: limit,
            rule: rule,
            now: start.addingTimeInterval(1)
        )
        XCTAssertEqual(deliveries, 1)

        evaluate(
            monitor,
            .diskAvailableCapacity,
            value: limit + 1,
            rule: rule,
            now: start.addingTimeInterval(2)
        )
        evaluate(
            monitor,
            .diskAvailableCapacity,
            value: limit,
            rule: rule,
            now: start.addingTimeInterval(3)
        )
        XCTAssertEqual(deliveries, 1)

        evaluate(
            monitor,
            .diskAvailableCapacity,
            value: limit,
            rule: rule,
            now: start.addingTimeInterval(901)
        )
        XCTAssertEqual(deliveries, 2)
    }

    func testThermalCriticalAndBatteryProviderValuesUseNativeSignals() {
        XCTAssertFalse(SystemConditionMonitor.isViolating(
            SystemConditionReading(.thermalState, value: 1),
            threshold: 2
        ))
        XCTAssertTrue(SystemConditionMonitor.isViolating(
            SystemConditionReading(.thermalState, value: 2),
            threshold: 2
        ))
        XCTAssertFalse(SystemConditionMonitor.isViolating(
            SystemConditionReading(.batteryService, value: 0),
            threshold: 1
        ))
        XCTAssertTrue(SystemConditionMonitor.isViolating(
            SystemConditionReading(.batteryService, value: 1),
            threshold: 1
        ))
    }

    func testUnavailableReadingDoesNotActivateOrDeliver() {
        var deliveries = 0
        var updates = 0
        let monitor = SystemConditionMonitor { _, _, _ in deliveries += 1 }
        monitor.onConditionUpdate = { _ in updates += 1 }
        let rule = SystemAlertRule(
            enabled: true,
            thresholdValue: 1,
            durationSeconds: 0,
            destinations: [.notification, .attentionLog]
        )

        monitor.evaluate(
            readings: [:],
            rules: [.batteryService: rule]
        )

        XCTAssertEqual(monitor.state(for: .batteryService), .normal)
        XCTAssertEqual(deliveries, 0)
        XCTAssertEqual(updates, 0)
    }

    func testSystemRuleRoundTripPreservesAllChoices() throws {
        let rule = SystemAlertRule(
            enabled: true,
            thresholdValue: 10 * 1_024 * 1_024 * 1_024,
            durationSeconds: 120,
            cooldownSeconds: 600,
            destinations: [.compactHealth, .attentionLog]
        )
        let encoded = try JSONEncoder().encode(rule)
        XCTAssertEqual(try JSONDecoder().decode(
            SystemAlertRule.self,
            from: encoded
        ), rule)
    }

    private func evaluate(
        _ monitor: SystemConditionMonitor,
        _ signal: SystemAlertSignal,
        value: Double,
        rule: SystemAlertRule,
        now: Date
    ) {
        monitor.evaluate(
            readings: [signal: SystemConditionReading(signal, value: value)],
            rules: [signal: rule],
            now: now
        )
    }
}
