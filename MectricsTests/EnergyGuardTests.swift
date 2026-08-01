import MetricsKit
import XCTest
@testable import Mectrics

final class EnergyGuardTests: XCTestCase {
    func testEveryPowerAndThermalInputSelectsExpectedPolicy() {
        XCTAssertEqual(
            EnergyGuardStateMachine.targetMode(input()),
            .normal
        )
        XCTAssertEqual(
            EnergyGuardStateMachine.targetMode(input(isOnBattery: true)),
            .reduced
        )
        XCTAssertEqual(
            EnergyGuardStateMachine.targetMode(
                input(isLowPowerModeEnabled: true)
            ),
            .reduced
        )
        XCTAssertEqual(
            EnergyGuardStateMachine.targetMode(
                input(thermalState: .serious)
            ),
            .protected
        )
        XCTAssertEqual(
            EnergyGuardStateMachine.targetMode(
                input(thermalState: .critical)
            ),
            .protected
        )
        XCTAssertEqual(
            EnergyGuardStateMachine.targetMode(input(isSleeping: true)),
            .protected
        )
        XCTAssertEqual(
            EnergyGuardStateMachine.targetMode(
                input(
                    isEnabled: false,
                    isOnBattery: true,
                    thermalState: .critical,
                    isSleeping: true
                )
            ),
            .normal
        )
    }

    func testVisibleHeavyDetailTemporarilyResumesThatProvider() {
        let protected = EnergyGuardStateMachine.decision(
            mode: .protected,
            visibleHeavyMetricIDs: [.gpu]
        )
        XCTAssertFalse(
            protected.runtimePolicy.pausedMetricIDs.contains(.gpu)
        )
        XCTAssertTrue(
            protected.runtimePolicy.pausedMetricIDs.contains(.sensors)
        )
        XCTAssertTrue(
            protected.runtimePolicy.pausedMetricIDs.contains(.fans)
        )

        let reduced = EnergyGuardStateMachine.decision(
            mode: .reduced,
            visibleHeavyMetricIDs: []
        )
        XCTAssertGreaterThan(
            reduced.runtimePolicy.intervalMultiplier,
            1
        )
    }

    func testEscalationIsImmediateAndRecoveryUsesHysteresis() {
        let machine = EnergyGuardStateMachine(
            minimumRecoveryInterval: 30
        )
        let start = Date(timeIntervalSince1970: 1_000)

        XCTAssertEqual(
            machine.update(
                input: input(isOnBattery: true),
                now: start
            ).mode,
            .reduced
        )
        XCTAssertEqual(
            machine.update(
                input: input(thermalState: .critical),
                now: start.addingTimeInterval(1)
            ).mode,
            .protected
        )
        XCTAssertEqual(
            machine.update(
                input: input(),
                now: start.addingTimeInterval(29)
            ).mode,
            .protected
        )
        XCTAssertEqual(
            machine.update(
                input: input(),
                now: start.addingTimeInterval(31)
            ).mode,
            .normal
        )
    }

    func testProtectedPolicyDoesLessHeavyWorkThanNormal() {
        let normal = EnergyGuardStateMachine.decision(
            mode: .normal,
            visibleHeavyMetricIDs: []
        ).runtimePolicy
        let protected = EnergyGuardStateMachine.decision(
            mode: .protected,
            visibleHeavyMetricIDs: []
        ).runtimePolicy

        XCTAssertGreaterThan(
            protected.intervalMultiplier,
            normal.intervalMultiplier
        )
        XCTAssertGreaterThan(
            protected.heavyEveryNCycles,
            normal.heavyEveryNCycles
        )
        XCTAssertTrue(
            protected.pausedMetricIDs.isSuperset(
                of: [.sensors, .fans]
            )
        )
        XCTAssertFalse(protected.pausedMetricIDs.contains(.cpu))
        XCTAssertFalse(protected.pausedMetricIDs.contains(.memory))
    }

    func testUnwatchedScreenProtectsWithoutClaimingTheMacIsAsleep() {
        let screenOff = input(isScreenUnwatched: true)
        XCTAssertEqual(EnergyGuardStateMachine.targetMode(screenOff), .protected)
        XCTAssertEqual(EnergyGuardStateMachine.reason(screenOff), .screenUnwatched)

        // Sleep is the stronger statement and keeps precedence.
        let asleep = input(isSleeping: true, isScreenUnwatched: true)
        XCTAssertEqual(EnergyGuardStateMachine.reason(asleep), .sleeping)

        // A watched screen on AC stays at full rate.
        XCTAssertEqual(EnergyGuardStateMachine.targetMode(input()), .normal)
    }

    func testUnwatchedScreenPausesEvenAVisibleDetailWindow() {
        let machine = EnergyGuardStateMachine()
        let decision = machine.update(
            input: input(
                isScreenUnwatched: true,
                visibleHeavyMetricIDs: [.gpu]
            )
        )
        XCTAssertEqual(decision.mode, .protected)
        XCTAssertTrue(decision.runtimePolicy.pausedMetricIDs.contains(.gpu))
    }

    /// Energy Guard and the thermal alert rule read one signal, so Mectrics eases off
    /// on exactly the states it would tell the user their Mac is being held back on.
    /// If these ever drift, the app is quietly sampling less while reporting nothing.
    func testGuardProtectsAtExactlyTheStatesTheThermalRuleReports() {
        let ruleThreshold = Double(ThermalPressureLevel.serious.rawValue)
        for level in ThermalPressureLevel.allCases {
            let reported = SystemConditionMonitor.isViolating(
                SystemConditionReading(
                    .thermalPressure,
                    value: Double(level.rawValue)
                ),
                threshold: ruleThreshold
            )
            let protected = EnergyGuardStateMachine.targetMode(
                input(thermalState: level)
            ) == .protected
            XCTAssertEqual(reported, protected, "thermal state \(level)")
            XCTAssertEqual(
                EnergyGuardStateMachine.reason(input(thermalState: level))
                    == .thermalState,
                protected,
                "thermal state \(level)"
            )
        }
    }

    /// A sustained window is the whole difference between "your Mac throttled" and
    /// "your Mac did a build". A single hot cycle must not alert.
    func testMomentaryThrottlingDoesNotAlertButASustainedStateDoes() {
        let monitor = SystemConditionMonitor()
        var transitions: [AlertConditionTransition] = []
        monitor.onConditionUpdate = { transitions.append($0.transition) }
        let start = Date(timeIntervalSince1970: 3_000)
        let rule = SystemAlertRule(
            enabled: true,
            thresholdValue: Double(ThermalPressureLevel.serious.rawValue),
            durationSeconds: 120,
            destinations: [.attentionLog]
        )

        evaluate(monitor, .serious, rule: rule, at: start)
        evaluate(monitor, .fair, rule: rule, at: start.addingTimeInterval(10))
        XCTAssertEqual(transitions, [.pending, .recovered])

        evaluate(monitor, .serious, rule: rule, at: start.addingTimeInterval(20))
        evaluate(monitor, .serious, rule: rule, at: start.addingTimeInterval(141))
        XCTAssertEqual(
            transitions,
            [.pending, .recovered, .pending, .activated]
        )
        XCTAssertEqual(monitor.state(for: .thermalPressure), .active)
    }

    private func evaluate(
        _ monitor: SystemConditionMonitor,
        _ level: ThermalPressureLevel,
        rule: SystemAlertRule,
        at now: Date
    ) {
        monitor.evaluate(
            readings: SystemConditionSource.readings(
                latest: [:],
                thermalLevel: level
            ),
            rules: [.thermalPressure: rule],
            now: now
        )
    }

    private func input(
        isEnabled: Bool = true,
        isOnBattery: Bool = false,
        isLowPowerModeEnabled: Bool = false,
        thermalState: EnergyThermalState = .nominal,
        isSleeping: Bool = false,
        isScreenUnwatched: Bool = false,
        visibleHeavyMetricIDs: Set<MetricID> = []
    ) -> EnergyGuardInput {
        EnergyGuardInput(
            isEnabled: isEnabled,
            isOnBattery: isOnBattery,
            isLowPowerModeEnabled: isLowPowerModeEnabled,
            thermalState: thermalState,
            isSleeping: isSleeping,
            isScreenUnwatched: isScreenUnwatched,
            visibleHeavyMetricIDs: visibleHeavyMetricIDs
        )
    }
}
