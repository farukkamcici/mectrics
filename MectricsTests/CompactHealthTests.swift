import MetricsKit
import XCTest
@testable import Mectrics

final class CompactHealthTests: XCTestCase {
    func testEveryCompactHealthFixtureResolvesDeterministically() {
        XCTAssertEqual(
            CompactHealthState.resolve(
                conditions: [],
                configuredMetricStates: []
            ),
            .normal
        )
        XCTAssertEqual(
            CompactHealthState.resolve(
                conditions: [condition(state: .pending)],
                configuredMetricStates: [.live]
            ),
            .pending
        )
        XCTAssertEqual(
            CompactHealthState.resolve(
                conditions: [condition(state: .active)],
                configuredMetricStates: [.live]
            ),
            .warning
        )
        XCTAssertEqual(
            CompactHealthState.resolve(
                conditions: [
                    condition(
                        state: .active,
                        conditionKey:
                            SystemAlertSignal.batteryService.conditionKey,
                        measured: 1
                    )
                ],
                configuredMetricStates: [.live]
            ),
            .critical
        )
        XCTAssertEqual(
            CompactHealthState.resolve(
                conditions: [],
                configuredMetricStates: [.stale, .live]
            ),
            .stale
        )
        XCTAssertEqual(
            CompactHealthState.resolve(
                conditions: [],
                configuredMetricStates: [.unavailable]
            ),
            .unavailable
        )
    }

    func testSeverityOutranksRecencyAndPending() {
        let warning = condition(
            state: .active,
            startedAt: Date(timeIntervalSince1970: 1)
        )
        let recentPending = condition(
            state: .pending,
            startedAt: Date(timeIntervalSince1970: 2)
        )
        XCTAssertEqual(
            CompactHealthState.resolve(
                conditions: [recentPending, warning],
                configuredMetricStates: [.live]
            ),
            .warning
        )
    }

    func testMenuBarSlotHasOneInvariantLength() {
        XCTAssertEqual(CompactHealthStatusItem.fixedLength, 26)
        XCTAssertTrue(
            Set(CompactHealthState.allCases.map { _ in
                CompactHealthStatusItem.fixedLength
            }).count == 1
        )
    }

    private func condition(
        state: AlertConditionState,
        conditionKey: String = "threshold.cpu",
        measured: Double = 95,
        startedAt: Date = Date(timeIntervalSince1970: 1)
    ) -> ActiveAlertCondition {
        ActiveAlertCondition(update: AlertConditionUpdate(
            conditionKey: conditionKey,
            metricID: .cpu,
            state: state,
            transition: state == .active ? .activated : .pending,
            measuredValue: measured,
            thresholdValue: 90,
            durationSeconds: 30,
            startedAt: startedAt,
            destinations: [.compactHealth]
        ))
    }
}
