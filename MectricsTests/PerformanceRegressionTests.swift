import MetricsKit
import XCTest
@testable import Mectrics

/// Microbenchmarks protect deterministic hot paths. Whole-process CPU, energy, and
/// footprint budgets belong to scripts/performance because a debugger changes them.
final class PerformanceRegressionTests: XCTestCase {
    func testMenuBarFormattingPerformance() {
        let sample = MetricSample(
            value: 0.67,
            detail: [
                "coreCount": 4,
                "core0": 0.2,
                "core1": 0.5,
                "core2": 0.8,
                "core3": 0.9,
                "used": 12_000_000_000,
                "free": 4_000_000_000,
                "down": 8_000_000,
                "up": 900_000
            ]
        )
        var renderedCount = 0

        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()]) {
            for _ in 0..<2_000 {
                for id in MetricID.allCases {
                    for component in MenuBarComponent.available(for: id) {
                        _ = MenuBarText.visual(
                            for: id,
                            component: component,
                            sample: sample,
                            temperature: 68
                        )
                        renderedCount += 1
                    }
                }
            }
        }

        XCTAssertGreaterThan(renderedCount, 0)
    }

    func testEnergyGuardDecisionPerformance() {
        // An unwatched screen is what reaches `.protected`, the only mode that pauses
        // heavy providers — and pausing is the branch this benchmark exists to time.
        let input = EnergyGuardInput(
            isEnabled: true,
            isOnBattery: true,
            isLowPowerModeEnabled: false,
            thermalState: .nominal,
            isSleeping: false,
            isScreenUnwatched: true,
            visibleHeavyMetricIDs: [.gpu]
        )
        var protectedCount = 0

        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()]) {
            for _ in 0..<50_000 {
                let decision = EnergyGuardStateMachine.decision(
                    mode: EnergyGuardStateMachine.targetMode(input),
                    visibleHeavyMetricIDs: input.visibleHeavyMetricIDs
                )
                if decision.runtimePolicy.pausedMetricIDs.contains(.sensors) {
                    protectedCount += 1
                }
            }
        }

        XCTAssertGreaterThan(protectedCount, 0)
    }
}
