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
            protected.runtimePolicy.pausedMetricIDs.contains(.bluetooth)
        )

        let reduced = EnergyGuardStateMachine.decision(
            mode: .reduced,
            visibleHeavyMetricIDs: [.bluetooth]
        )
        XCTAssertFalse(
            reduced.runtimePolicy.pausedMetricIDs.contains(.bluetooth)
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
                of: [.sensors, .bluetooth]
            )
        )
        XCTAssertFalse(protected.pausedMetricIDs.contains(.cpu))
        XCTAssertFalse(protected.pausedMetricIDs.contains(.memory))
    }

    private func input(
        isEnabled: Bool = true,
        isOnBattery: Bool = false,
        isLowPowerModeEnabled: Bool = false,
        thermalState: EnergyThermalState = .nominal,
        isSleeping: Bool = false
    ) -> EnergyGuardInput {
        EnergyGuardInput(
            isEnabled: isEnabled,
            isOnBattery: isOnBattery,
            isLowPowerModeEnabled: isLowPowerModeEnabled,
            thermalState: thermalState,
            isSleeping: isSleeping,
            visibleHeavyMetricIDs: []
        )
    }
}
