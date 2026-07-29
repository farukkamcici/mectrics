import MetricsKit
import XCTest
@testable import Mectrics

final class AlertRuleTests: XCTestCase {
    func testLegacyEnabledRulePreservesNotificationAndAddsLifecycleLog() throws {
        let data = Data(
            """
            {
              "enabled": true,
              "thresholdPercent": 85,
              "durationSeconds": 60
            }
            """.utf8
        )

        let rule = try JSONDecoder().decode(AlertRule.self, from: data)

        XCTAssertTrue(rule.enabled)
        XCTAssertEqual(rule.thresholdPercent, 85)
        XCTAssertEqual(rule.durationSeconds, 60)
        XCTAssertEqual(rule.cooldownSeconds, 15 * 60)
        XCTAssertEqual(rule.destinations, [.notification, .attentionLog])
    }

    func testLegacyDisabledRuleDoesNotOptIntoNotifications() throws {
        let data = Data(
            """
            {
              "enabled": false,
              "thresholdPercent": 90,
              "durationSeconds": 30
            }
            """.utf8
        )

        let rule = try JSONDecoder().decode(AlertRule.self, from: data)

        XCTAssertEqual(rule.destinations, [.attentionLog])
    }

    func testOneViolationProducesOneActivationAndOneRecovery() {
        var notifications: [(MetricID, Int)] = []
        var updates: [AlertConditionUpdate] = []
        let monitor = ThresholdMonitor { id, _, measured in
            notifications.append((id, measured))
        }
        monitor.onConditionUpdate = { updates.append($0) }
        let start = Date(timeIntervalSince1970: 1_000)
        let rule = AlertRule(
            enabled: true,
            thresholdPercent: 80,
            durationSeconds: 30,
            destinations: [.notification, .compactHealth, .attentionLog]
        )

        monitor.evaluate(
            latest: [.cpu: MetricSample(value: 0.9)],
            rules: [.cpu: rule],
            now: start
        )
        monitor.evaluate(
            latest: [.cpu: MetricSample(value: 0.92)],
            rules: [.cpu: rule],
            now: start.addingTimeInterval(31)
        )
        monitor.evaluate(
            latest: [.cpu: MetricSample(value: 0.95)],
            rules: [.cpu: rule],
            now: start.addingTimeInterval(60)
        )
        monitor.evaluate(
            latest: [.cpu: MetricSample(value: 0.4)],
            rules: [.cpu: rule],
            now: start.addingTimeInterval(61)
        )

        XCTAssertEqual(updates.map(\.transition), [.pending, .activated, .recovered])
        XCTAssertEqual(notifications.count, 1)
        XCTAssertEqual(notifications.first?.0, .cpu)
        XCTAssertEqual(monitor.state(for: .cpu), .normal)
    }

    func testLogOnlyRuleNeverSendsNotification() {
        var notificationCount = 0
        let monitor = ThresholdMonitor { _, _, _ in notificationCount += 1 }
        let rule = AlertRule(
            enabled: true,
            thresholdPercent: 80,
            durationSeconds: 0,
            destinations: [.attentionLog]
        )

        monitor.evaluate(
            latest: [.memory: MetricSample(value: 0.9)],
            rules: [.memory: rule],
            now: Date(timeIntervalSince1970: 2_000)
        )

        XCTAssertEqual(monitor.state(for: .memory), .active)
        XCTAssertEqual(notificationCount, 0)
    }

    func testDisabledRuleProducesNoUpdatesOrNotifications() {
        var updateCount = 0
        var notificationCount = 0
        let monitor = ThresholdMonitor { _, _, _ in notificationCount += 1 }
        monitor.onConditionUpdate = { _ in updateCount += 1 }
        let rule = AlertRule(
            enabled: false,
            thresholdPercent: 1,
            durationSeconds: 0,
            destinations: [.notification, .compactHealth, .attentionLog]
        )

        monitor.evaluate(
            latest: [.cpu: MetricSample(value: 1)],
            rules: [.cpu: rule],
            now: Date(timeIntervalSince1970: 3_000)
        )

        XCTAssertEqual(updateCount, 0)
        XCTAssertEqual(notificationCount, 0)
        XCTAssertEqual(monitor.state(for: .cpu), .normal)
    }

    func testCooldownDelaysASecondActivationWithoutDuplicatingIt() {
        var transitions: [AlertConditionTransition] = []
        let monitor = ThresholdMonitor(notificationHandler: { _, _, _ in })
        monitor.onConditionUpdate = { transitions.append($0.transition) }
        let rule = AlertRule(
            enabled: true,
            thresholdPercent: 80,
            durationSeconds: 0,
            cooldownSeconds: 60,
            destinations: [.attentionLog]
        )
        let start = Date(timeIntervalSince1970: 4_000)

        monitor.evaluate(
            latest: [.cpu: MetricSample(value: 0.9)],
            rules: [.cpu: rule],
            now: start
        )
        monitor.evaluate(
            latest: [.cpu: MetricSample(value: 0.4)],
            rules: [.cpu: rule],
            now: start.addingTimeInterval(1)
        )
        monitor.evaluate(
            latest: [.cpu: MetricSample(value: 0.9)],
            rules: [.cpu: rule],
            now: start.addingTimeInterval(10)
        )
        monitor.evaluate(
            latest: [.cpu: MetricSample(value: 0.9)],
            rules: [.cpu: rule],
            now: start.addingTimeInterval(61)
        )

        XCTAssertEqual(
            transitions,
            [.pending, .activated, .recovered, .pending, .activated]
        )
    }
}
