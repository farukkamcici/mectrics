import AppKit
import MetricsKit

enum EnergyGuardMode: String, Codable, CaseIterable, Equatable {
    case normal
    case reduced
    case protected

    var rank: Int {
        switch self {
        case .normal: return 0
        case .reduced: return 1
        case .protected: return 2
        }
    }

    var localizedName: String {
        switch self {
        case .normal:
            return String(
                localized: "energyGuard.mode.normal",
                defaultValue: "Normal"
            )
        case .reduced:
            return String(
                localized: "energyGuard.mode.reduced",
                defaultValue: "Reduced"
            )
        case .protected:
            return String(
                localized: "energyGuard.mode.protected",
                defaultValue: "Protected"
            )
        }
    }
}

enum EnergyThermalState: Int, Equatable {
    case nominal
    case fair
    case serious
    case critical

    init(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal: self = .nominal
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        @unknown default: self = .nominal
        }
    }
}

struct EnergyGuardInput: Equatable {
    var isEnabled: Bool
    var isOnBattery: Bool
    var isLowPowerModeEnabled: Bool
    var thermalState: EnergyThermalState
    var isSleeping: Bool
    var visibleHeavyMetricIDs: Set<MetricID>
}

struct EnergyGuardDecision: Equatable {
    let mode: EnergyGuardMode
    let runtimePolicy: SamplingRuntimePolicy
}

/// Pure deterministic state machine with immediate escalation and a short recovery
/// hold, preventing power/thermal boundary chatter from repeatedly reconfiguring the
/// sampler.
final class EnergyGuardStateMachine {
    private(set) var mode: EnergyGuardMode = .normal
    private var lastTransitionAt = Date.distantPast
    private let minimumRecoveryInterval: TimeInterval

    init(minimumRecoveryInterval: TimeInterval = 30) {
        self.minimumRecoveryInterval = minimumRecoveryInterval
    }

    func update(
        input: EnergyGuardInput,
        now: Date = Date()
    ) -> EnergyGuardDecision {
        let target = Self.targetMode(input)
        if target != mode {
            let isEscalating = target.rank > mode.rank
            if isEscalating
                || now.timeIntervalSince(lastTransitionAt)
                    >= minimumRecoveryInterval {
                mode = target
                lastTransitionAt = now
            }
        }
        return Self.decision(
            mode: mode,
            visibleHeavyMetricIDs: input.isSleeping
                ? []
                : input.visibleHeavyMetricIDs
        )
    }

    static func targetMode(_ input: EnergyGuardInput) -> EnergyGuardMode {
        guard input.isEnabled else { return .normal }
        if input.isSleeping
            || input.thermalState == .serious
            || input.thermalState == .critical {
            return .protected
        }
        if input.isLowPowerModeEnabled || input.isOnBattery {
            return .reduced
        }
        return .normal
    }

    static func decision(
        mode: EnergyGuardMode,
        visibleHeavyMetricIDs: Set<MetricID>
    ) -> EnergyGuardDecision {
        let allHeavy: Set<MetricID> = [
            .sensors, .bluetooth, .fans, .gpu
        ]
        let policy: SamplingRuntimePolicy
        switch mode {
        case .normal:
            policy = SamplingRuntimePolicy(
                intervalMultiplier: 1,
                heavyEveryNCycles: 3
            )
        case .reduced:
            policy = SamplingRuntimePolicy(
                intervalMultiplier: 1.5,
                heavyEveryNCycles: 5,
                pausedMetricIDs: Set<MetricID>([.bluetooth])
                    .subtracting(visibleHeavyMetricIDs)
            )
        case .protected:
            policy = SamplingRuntimePolicy(
                intervalMultiplier: 3,
                heavyEveryNCycles: 8,
                pausedMetricIDs:
                    allHeavy.subtracting(visibleHeavyMetricIDs)
            )
        }
        return EnergyGuardDecision(mode: mode, runtimePolicy: policy)
    }
}

@MainActor
final class EnergyGuardController: NSObject {
    private let model: AppModel
    private let stateMachine: EnergyGuardStateMachine
    private var onBattery = false
    private var isSleeping = false
    private var visibleHeavyMetricIDs: Set<MetricID> = []
    private var lastMode = EnergyGuardMode.normal

    init(
        model: AppModel,
        stateMachine: EnergyGuardStateMachine = EnergyGuardStateMachine()
    ) {
        self.model = model
        self.stateMachine = stateMachine
        super.init()
    }

    func start(onBattery: Bool) {
        self.onBattery = onBattery
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(processConditionsChanged),
            name: .NSProcessInfoPowerStateDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(processConditionsChanged),
            name: ProcessInfo.thermalStateDidChangeNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        recompute()
    }

    func stop() {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    func updatePowerSource(onBattery: Bool) {
        self.onBattery = onBattery
        recompute()
    }

    func updateVisibleHeavyMetrics(_ ids: Set<MetricID>) {
        visibleHeavyMetricIDs = ids.intersection([
            .sensors, .bluetooth, .fans, .gpu
        ])
        recompute()
    }

    func preferenceChanged() {
        recompute()
    }

    @objc private func processConditionsChanged() {
        recompute()
    }

    @objc private func workspaceWillSleep() {
        isSleeping = true
        recompute()
    }

    @objc private func workspaceDidWake() {
        isSleeping = false
        recompute()
        model.refreshMetrics()
    }

    private func recompute(now: Date = Date()) {
        let info = ProcessInfo.processInfo
        let decision = stateMachine.update(
            input: EnergyGuardInput(
                isEnabled: model.adaptMonitoringToEnergyState,
                isOnBattery: onBattery,
                isLowPowerModeEnabled: info.isLowPowerModeEnabled,
                thermalState: EnergyThermalState(info.thermalState),
                isSleeping: isSleeping,
                visibleHeavyMetricIDs: visibleHeavyMetricIDs
            ),
            now: now
        )
        model.engine.updateRuntimePolicy(decision.runtimePolicy)
        model.energyGuardMode = decision.mode
        if decision.mode != lastMode {
            recordTransition(
                from: lastMode,
                to: decision.mode,
                at: now
            )
            lastMode = decision.mode
        }
    }

    private func recordTransition(
        from oldMode: EnergyGuardMode,
        to newMode: EnergyGuardMode,
        at date: Date
    ) {
        let isRecovery = newMode == .normal
        model.attentionLog.apply(AlertConditionUpdate(
            conditionKey: "system.energyGuard",
            metricID: .sensors,
            state: isRecovery ? .normal : .active,
            transition: isRecovery ? .recovered : .activated,
            measuredValue: Double(newMode.rank),
            unit: .count,
            thresholdValue: 1,
            durationSeconds: 0,
            startedAt: isRecovery ? nil : date,
            destinations: [.attentionLog]
        ), at: date)
    }
}
