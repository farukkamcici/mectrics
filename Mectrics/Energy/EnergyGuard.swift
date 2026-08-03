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

/// The guard and the thermal alert rule read the same signal, so they share one
/// definition: what makes Mectrics sample less often is exactly what tells the user
/// their Mac is being held back.
typealias EnergyThermalState = ThermalPressureLevel

struct EnergyGuardInput: Equatable {
    var isEnabled: Bool
    var isOnBattery: Bool
    var isLowPowerModeEnabled: Bool
    var thermalState: EnergyThermalState
    var isSleeping: Bool
    /// The display is off, the screen is locked, or another user's session is in
    /// front — the menu bar exists but nobody can read it.
    var isScreenUnwatched: Bool
    var visibleHeavyMetricIDs: Set<MetricID>

    /// No reading can reach a person right now.
    var isUnobservable: Bool { isSleeping || isScreenUnwatched }
}

/// Why the guard settled on its current mode. Shown next to the mode so the policy
/// is never an unexplained label.
enum EnergyGuardReason: Equatable {
    case disabled
    case sleeping
    case screenUnwatched
    case thermalState
    case lowPowerMode
    case onBattery
    case none

    var localizedName: String {
        switch self {
        case .disabled:
            return String(
                localized: "energyGuard.reason.disabled",
                defaultValue: "adapting is off"
            )
        case .sleeping:
            return String(
                localized: "energyGuard.reason.sleeping",
                defaultValue: "the Mac is asleep"
            )
        case .screenUnwatched:
            return String(
                localized: "energyGuard.reason.screenUnwatched",
                defaultValue: "the screen is off"
            )
        case .thermalState:
            return String(
                localized: "energyGuard.reason.thermal",
                defaultValue: "the Mac is running hot"
            )
        case .lowPowerMode:
            return String(
                localized: "energyGuard.reason.lowPowerMode",
                defaultValue: "Low Power Mode is on"
            )
        case .onBattery:
            return String(
                localized: "energyGuard.reason.onBattery",
                defaultValue: "on battery"
            )
        case .none:
            return String(
                localized: "energyGuard.reason.none",
                defaultValue: "plugged in and cool"
            )
        }
    }
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
            visibleHeavyMetricIDs: input.isUnobservable
                ? []
                : input.visibleHeavyMetricIDs
        )
    }

    static func targetMode(_ input: EnergyGuardInput) -> EnergyGuardMode {
        guard input.isEnabled else { return .normal }
        if input.isUnobservable
            || input.thermalState == .serious
            || input.thermalState == .critical {
            return .protected
        }
        if input.isLowPowerModeEnabled || input.isOnBattery {
            return .reduced
        }
        return .normal
    }

    /// The single condition that decided the mode, following the same precedence as
    /// `targetMode`.
    static func reason(_ input: EnergyGuardInput) -> EnergyGuardReason {
        guard input.isEnabled else { return .disabled }
        if input.isSleeping { return .sleeping }
        if input.isScreenUnwatched { return .screenUnwatched }
        if input.thermalState == .serious
            || input.thermalState == .critical {
            return .thermalState
        }
        if input.isLowPowerModeEnabled { return .lowPowerMode }
        if input.isOnBattery { return .onBattery }
        return .none
    }

    static func decision(
        mode: EnergyGuardMode,
        visibleHeavyMetricIDs: Set<MetricID>
    ) -> EnergyGuardDecision {
        let allHeavy: Set<MetricID> = [.sensors, .fans, .gpu]
        let policy: SamplingRuntimePolicy
        switch mode {
        case .normal:
            // Battery charge and disk capacity move on the scale of minutes, and both
            // cost an IOKit round trip, so reading them on every base cycle buys a
            // number nobody can see change. Every second cycle is 2 s on AC and 4 s on
            // battery — well inside `MetricDataState`'s 15-second staleness budget.
            policy = SamplingRuntimePolicy(
                intervalMultiplier: 1,
                mediumEveryNCycles: 2,
                heavyEveryNCycles: 3
            )
        case .reduced:
            policy = SamplingRuntimePolicy(
                intervalMultiplier: 1.5,
                mediumEveryNCycles: 2,
                heavyEveryNCycles: 5
            )
        case .protected:
            // Battery and disk must still refresh inside `MetricDataState`'s 15-second
            // staleness budget, and the slowest case is 2 s on battery × 3 × 2 = 12 s.
            policy = SamplingRuntimePolicy(
                intervalMultiplier: 3,
                mediumEveryNCycles: 2,
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
    private var isScreenAsleep = false
    private var isScreenLocked = false
    private var isSessionInBackground = false
    private var visibleHeavyMetricIDs: Set<MetricID> = []
    private var lastMode = EnergyGuardMode.normal
    private var lastReason = EnergyGuardReason.none

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
        // A dark display, a locked screen, and a switched-away session all leave the
        // menu bar unreadable while the Mac itself stays awake — exactly the hours a
        // laptop spends on battery with the lid open.
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(screensDidSleep),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(screensDidWake),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(sessionDidResignActive),
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(sessionDidBecomeActive),
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )
        // Screen locking has no AppKit notification; the distributed one is what
        // every Mac utility uses.
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(screenDidLock),
            name: Notification.Name("com.apple.screenIsLocked"),
            object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(screenDidUnlock),
            name: Notification.Name("com.apple.screenIsUnlocked"),
            object: nil
        )
        recompute()
    }

    func stop() {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
    }

    func updatePowerSource(onBattery: Bool) {
        self.onBattery = onBattery
        recompute()
    }

    func updateVisibleHeavyMetrics(_ ids: Set<MetricID>) {
        visibleHeavyMetricIDs = ids.intersection([.sensors, .fans, .gpu])
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

    @objc private func screensDidSleep() {
        isScreenAsleep = true
        recompute()
    }

    @objc private func screensDidWake() {
        isScreenAsleep = false
        resumeWatching()
    }

    @objc private func screenDidLock() {
        isScreenLocked = true
        recompute()
    }

    @objc private func screenDidUnlock() {
        isScreenLocked = false
        resumeWatching()
    }

    @objc private func sessionDidResignActive() {
        isSessionInBackground = true
        recompute()
    }

    @objc private func sessionDidBecomeActive() {
        isSessionInBackground = false
        resumeWatching()
    }

    /// Whoever is back at the Mac must not be shown a stale reading, so the first
    /// full pass happens immediately rather than on the next scheduled cycle.
    private func resumeWatching() {
        recompute()
        model.refreshMetrics()
    }

    private func recompute(now: Date = Date()) {
        let info = ProcessInfo.processInfo
        let input = EnergyGuardInput(
            isEnabled: model.adaptMonitoringToEnergyState,
            isOnBattery: onBattery,
            isLowPowerModeEnabled: info.isLowPowerModeEnabled,
            thermalState: EnergyThermalState(info.thermalState),
            isSleeping: isSleeping,
            isScreenUnwatched: isScreenAsleep
                || isScreenLocked
                || isSessionInBackground,
            visibleHeavyMetricIDs: visibleHeavyMetricIDs
        )
        let decision = stateMachine.update(input: input, now: now)
        let reason = EnergyGuardStateMachine.reason(input)
        model.engine.updateRuntimePolicy(decision.runtimePolicy)
        model.energyGuardMode = decision.mode
        model.energyGuardReason = reason
        if decision.mode != lastMode {
            // Locking the screen or letting the display sleep happens several times a
            // day and says nothing about the Mac's health. Recording it would bury the
            // power and thermal events the log exists for.
            if reason != .screenUnwatched, lastReason != .screenUnwatched {
                recordTransition(
                    from: lastMode,
                    to: decision.mode,
                    at: now
                )
            }
            lastMode = decision.mode
        }
        lastReason = reason
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
