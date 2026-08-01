import Foundation

/// Evaluates native system signals independently of percentage-based metric rules.
public final class SystemConditionMonitor {
    public typealias NotificationHandler = (
        SystemAlertSignal,
        SystemAlertRule,
        SystemConditionReading
    ) -> Void

    public var onConditionUpdate: ((AlertConditionUpdate) -> Void)?

    private var lastFired: [SystemAlertSignal: Date] = [:]
    private var violationStartedAt: [SystemAlertSignal: Date] = [:]
    private var states: [SystemAlertSignal: AlertConditionState] = [:]
    private let notificationHandler: NotificationHandler

    public init(
        notificationHandler: @escaping NotificationHandler = { _, _, _ in }
    ) {
        self.notificationHandler = notificationHandler
    }

    public func state(for signal: SystemAlertSignal) -> AlertConditionState {
        states[signal] ?? .normal
    }

    public func evaluate(
        readings: [SystemAlertSignal: SystemConditionReading],
        rules: [SystemAlertSignal: SystemAlertRule],
        now: Date = Date()
    ) {
        for (signal, rule) in rules where rule.enabled {
            guard let reading = readings[signal] else {
                clearUnavailable(signal)
                continue
            }

            guard Self.isViolating(reading, threshold: rule.thresholdValue) else {
                recoverIfNeeded(signal: signal, reading: reading, rule: rule)
                continue
            }

            let startedAt = violationStartedAt[signal] ?? now
            if violationStartedAt[signal] == nil {
                violationStartedAt[signal] = startedAt
                emit(
                    .pending,
                    transition: .pending,
                    signal: signal,
                    reading: reading,
                    rule: rule,
                    startedAt: startedAt
                )
            }

            guard now.timeIntervalSince(startedAt) >= Double(rule.durationSeconds),
                  state(for: signal) != .active,
                  now.timeIntervalSince(lastFired[signal] ?? .distantPast)
                    >= Double(rule.cooldownSeconds)
            else { continue }

            lastFired[signal] = now
            emit(
                .active,
                transition: .activated,
                signal: signal,
                reading: reading,
                rule: rule,
                startedAt: startedAt
            )
            if rule.destinations.contains(.notification) {
                notificationHandler(signal, rule, reading)
            }
        }

        let enabledSignals = Set(
            rules.compactMap { $0.value.enabled ? $0.key : nil }
        )
        for signal in Set(states.keys).subtracting(enabledSignals) {
            clearUnavailable(signal)
        }
    }

    public static func isViolating(
        _ reading: SystemConditionReading,
        threshold: Double
    ) -> Bool {
        switch reading.signal {
        case .diskAvailableCapacity:
            return reading.value <= threshold
        case .thermalPressure, .memoryPressure, .batteryService:
            return reading.value >= threshold
        }
    }

    private func recoverIfNeeded(
        signal: SystemAlertSignal,
        reading: SystemConditionReading,
        rule: SystemAlertRule
    ) {
        let priorState = state(for: signal)
        let startedAt = violationStartedAt[signal]
        violationStartedAt[signal] = nil
        states[signal] = .normal
        guard priorState != .normal else { return }
        onConditionUpdate?(makeUpdate(
            state: .normal,
            transition: .recovered,
            signal: signal,
            reading: reading,
            rule: rule,
            startedAt: startedAt
        ))
    }

    private func clearUnavailable(_ signal: SystemAlertSignal) {
        violationStartedAt[signal] = nil
        states[signal] = .normal
    }

    private func emit(
        _ state: AlertConditionState,
        transition: AlertConditionTransition,
        signal: SystemAlertSignal,
        reading: SystemConditionReading,
        rule: SystemAlertRule,
        startedAt: Date?
    ) {
        states[signal] = state
        onConditionUpdate?(makeUpdate(
            state: state,
            transition: transition,
            signal: signal,
            reading: reading,
            rule: rule,
            startedAt: startedAt
        ))
    }

    private func makeUpdate(
        state: AlertConditionState,
        transition: AlertConditionTransition,
        signal: SystemAlertSignal,
        reading: SystemConditionReading,
        rule: SystemAlertRule,
        startedAt: Date?
    ) -> AlertConditionUpdate {
        AlertConditionUpdate(
            conditionKey: signal.conditionKey,
            metricID: signal.metricID,
            state: state,
            transition: transition,
            measuredValue: reading.value,
            unit: signal.unit,
            thresholdValue: rule.thresholdValue,
            durationSeconds: rule.durationSeconds,
            startedAt: startedAt,
            destinations: rule.destinations
        )
    }
}
