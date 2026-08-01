import Foundation

/// Evaluates metric threshold rules as a small incident state machine.
public final class ThresholdMonitor {
    public typealias NotificationHandler = (MetricID, AlertRule, Int) -> Void

    public var onConditionUpdate: ((AlertConditionUpdate) -> Void)?

    private var lastFired: [MetricID: Date] = [:]
    private var violationStartedAt: [MetricID: Date] = [:]
    private var states: [MetricID: AlertConditionState] = [:]
    private let notificationHandler: NotificationHandler

    public init(
        notificationHandler: @escaping NotificationHandler = { _, _, _ in }
    ) {
        self.notificationHandler = notificationHandler
    }

    public func state(for metricID: MetricID) -> AlertConditionState {
        states[metricID] ?? .normal
    }

    public func evaluate(
        latest: [MetricID: MetricSample],
        rules: [MetricID: AlertRule],
        now: Date = Date()
    ) {
        for (id, rule) in rules where rule.enabled {
            guard let sample = latest[id] else { continue }
            let measured = sample.unit == .celsius ? sample.value : sample.value * 100
            let violating = Self.isBelowRule(id)
                ? measured <= Double(rule.thresholdPercent)
                : measured >= Double(rule.thresholdPercent)

            guard violating else {
                recoverIfNeeded(
                    metricID: id,
                    measured: measured,
                    rule: rule,
                    destinations: rule.destinations
                )
                continue
            }

            let startedAt = violationStartedAt[id] ?? now
            if violationStartedAt[id] == nil {
                violationStartedAt[id] = startedAt
                setState(
                    .pending,
                    transition: .pending,
                    metricID: id,
                    measured: measured,
                    rule: rule,
                    startedAt: startedAt,
                    destinations: rule.destinations
                )
            }

            guard now.timeIntervalSince(startedAt) >= Double(rule.durationSeconds),
                  state(for: id) != .active,
                  now.timeIntervalSince(lastFired[id] ?? .distantPast)
                    >= Double(rule.cooldownSeconds)
            else { continue }

            lastFired[id] = now
            setState(
                .active,
                transition: .activated,
                metricID: id,
                measured: measured,
                rule: rule,
                startedAt: startedAt,
                destinations: rule.destinations
            )
            if rule.destinations.contains(.notification) {
                notificationHandler(id, rule, Int(measured.rounded()))
            }
        }

        let enabledIDs = Set(rules.compactMap { $0.value.enabled ? $0.key : nil })
        for id in Set(states.keys).subtracting(enabledIDs) {
            violationStartedAt[id] = nil
            states[id] = .normal
        }
    }

    /// Battery alerts below its threshold; all other metric rules alert above it.
    public static func isBelowRule(_ id: MetricID) -> Bool { id == .battery }

    private func recoverIfNeeded(
        metricID: MetricID,
        measured: Double,
        rule: AlertRule,
        destinations: Set<AlertDestination>
    ) {
        let priorState = state(for: metricID)
        let startedAt = violationStartedAt[metricID]
        violationStartedAt[metricID] = nil
        states[metricID] = .normal
        guard priorState != .normal else { return }
        onConditionUpdate?(AlertConditionUpdate(
            metricID: metricID,
            state: .normal,
            transition: .recovered,
            measuredValue: measured,
            thresholdValue: Double(rule.thresholdPercent),
            durationSeconds: rule.durationSeconds,
            startedAt: startedAt,
            destinations: destinations
        ))
    }

    private func setState(
        _ state: AlertConditionState,
        transition: AlertConditionTransition,
        metricID: MetricID,
        measured: Double,
        rule: AlertRule,
        startedAt: Date?,
        destinations: Set<AlertDestination>
    ) {
        states[metricID] = state
        onConditionUpdate?(AlertConditionUpdate(
            metricID: metricID,
            state: state,
            transition: transition,
            measuredValue: measured,
            thresholdValue: Double(rule.thresholdPercent),
            durationSeconds: rule.durationSeconds,
            startedAt: startedAt,
            destinations: destinations
        ))
    }
}
