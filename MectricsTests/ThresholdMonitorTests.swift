import MetricsKit
import XCTest
@testable import Mectrics

final class ThresholdMonitorTests: XCTestCase {
    func testLegacyEnabledRulePreservesNotificationAndAddsLocalLifecycle() throws {
        let legacy = Data(
            #"{"enabled":true,"thresholdPercent":85,"durationSeconds":60}"#.utf8
        )
        let rule = try JSONDecoder().decode(AlertRule.self, from: legacy)

        XCTAssertTrue(rule.enabled)
        XCTAssertEqual(rule.thresholdPercent, 85)
        XCTAssertEqual(rule.durationSeconds, 60)
        XCTAssertEqual(rule.cooldownSeconds, 15 * 60)
        XCTAssertEqual(rule.destinations, [.notification, .attentionLog])
    }

    func testLegacyDisabledRuleDoesNotEnableNotification() throws {
        let legacy = Data(
            #"{"enabled":false,"thresholdPercent":20}"#.utf8
        )
        let rule = try JSONDecoder().decode(AlertRule.self, from: legacy)

        XCTAssertFalse(rule.enabled)
        XCTAssertEqual(rule.destinations, [.attentionLog])
    }

    func testSustainedViolationActivatesOnceAndRecoveryClosesIncident() {
        var notifications = 0
        var updates: [AlertConditionUpdate] = []
        let monitor = ThresholdMonitor { _, _, _ in notifications += 1 }
        monitor.onConditionUpdate = { updates.append($0) }
        let start = Date(timeIntervalSince1970: 1_000)
        let rule = AlertRule(
            enabled: true,
            thresholdPercent: 80,
            durationSeconds: 30,
            destinations: [.notification, .attentionLog, .compactHealth]
        )

        monitor.evaluate(
            latest: [.cpu: MetricSample(value: 0.90)],
            rules: [.cpu: rule],
            now: start
        )
        monitor.evaluate(
            latest: [.cpu: MetricSample(value: 0.95)],
            rules: [.cpu: rule],
            now: start.addingTimeInterval(29)
        )
        XCTAssertEqual(monitor.state(for: .cpu), .pending)
        XCTAssertEqual(notifications, 0)

        monitor.evaluate(
            latest: [.cpu: MetricSample(value: 0.96)],
            rules: [.cpu: rule],
            now: start.addingTimeInterval(30)
        )
        monitor.evaluate(
            latest: [.cpu: MetricSample(value: 0.97)],
            rules: [.cpu: rule],
            now: start.addingTimeInterval(60)
        )
        XCTAssertEqual(monitor.state(for: .cpu), .active)
        XCTAssertEqual(notifications, 1)

        monitor.evaluate(
            latest: [.cpu: MetricSample(value: 0.20)],
            rules: [.cpu: rule],
            now: start.addingTimeInterval(61)
        )
        XCTAssertEqual(monitor.state(for: .cpu), .normal)
        XCTAssertEqual(
            updates.map(\.transition),
            [.pending, .activated, .recovered]
        )
    }

    func testCooldownAndDisabledRulesPreventDuplicateDelivery() {
        var notifications = 0
        let monitor = ThresholdMonitor { _, _, _ in notifications += 1 }
        let start = Date(timeIntervalSince1970: 2_000)
        let rule = AlertRule(
            enabled: true,
            thresholdPercent: 80,
            durationSeconds: 0,
            cooldownSeconds: 900,
            destinations: [.notification]
        )

        monitor.evaluate(
            latest: [.memory: MetricSample(value: 0.90)],
            rules: [.memory: rule],
            now: start
        )
        monitor.evaluate(
            latest: [.memory: MetricSample(value: 0.20)],
            rules: [.memory: rule],
            now: start.addingTimeInterval(1)
        )
        monitor.evaluate(
            latest: [.memory: MetricSample(value: 0.90)],
            rules: [.memory: rule],
            now: start.addingTimeInterval(2)
        )
        XCTAssertEqual(monitor.state(for: .memory), .pending)
        XCTAssertEqual(notifications, 1)

        monitor.evaluate(
            latest: [.memory: MetricSample(value: 0.90)],
            rules: [.memory: rule],
            now: start.addingTimeInterval(900)
        )
        XCTAssertEqual(notifications, 2)

        var disabledRule = rule
        disabledRule.enabled = false
        monitor.evaluate(
            latest: [.memory: MetricSample(value: 0.99)],
            rules: [.memory: disabledRule],
            now: start.addingTimeInterval(1_800)
        )
        XCTAssertEqual(monitor.state(for: .memory), .normal)
        XCTAssertEqual(notifications, 2)
    }

    func testBatteryUsesBelowThresholdSemantics() {
        var notifications = 0
        let monitor = ThresholdMonitor { _, _, _ in notifications += 1 }
        let rule = AlertRule(
            enabled: true,
            thresholdPercent: 20,
            durationSeconds: 0,
            destinations: [.notification]
        )

        monitor.evaluate(
            latest: [.battery: MetricSample(value: 0.21)],
            rules: [.battery: rule]
        )
        XCTAssertEqual(monitor.state(for: .battery), .normal)

        monitor.evaluate(
            latest: [.battery: MetricSample(value: 0.20)],
            rules: [.battery: rule]
        )
        XCTAssertEqual(monitor.state(for: .battery), .active)
        XCTAssertEqual(notifications, 1)
    }
}
