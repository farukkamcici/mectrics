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

    func testEveryUnitRendersWithItsUnitAttached() {
        // The network row used to fall through to a bare, locale-grouped number.
        XCTAssertEqual(value(1022.5, .bytesPerSecond), "1022.5 B/s")
        XCTAssertEqual(value(542_412, .bytesPerSecond), "529.7 KB/s")
        XCTAssertEqual(value(0.761, .fraction), "76%")
        XCTAssertEqual(value(74, .percent), "74%")
        XCTAssertEqual(value(51.6, .celsius), "52°C")
        XCTAssertEqual(value(2_400, .rpm), "2400 RPM")
        XCTAssertEqual(value(1_610_612_736, .bytes), "1.5 GB")
        XCTAssertEqual(value(12.34, .watts), "12.3 W")
        XCTAssertEqual(value(565, .count), "565")
    }

    func testValuesCarryNoLocaleGroupingOrDecimalSeparator() {
        // Menu bar and popover readings stay unlocalized (AGENTS.md §2), so a
        // Turkish or German locale must not turn "1022.5" into "1.022,5".
        for unit in [MetricUnit.bytesPerSecond, .bytes, .rpm, .watts, .count] {
            let text = value(1022.5, unit)
            XCTAssertFalse(text.contains(","), "\(unit) produced a comma: \(text)")
        }
    }

    private func value(_ number: Double, _ unit: MetricUnit) -> String {
        CompactHealthValue.text(
            for: MetricSample(value: number, unit: unit, detail: [:])
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
