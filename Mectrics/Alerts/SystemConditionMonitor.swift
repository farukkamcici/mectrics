import Foundation
import MetricsKit
import UserNotifications

/// Conditions macOS reports directly, rather than thresholds on a sampled value.
///
/// Kernel memory pressure and thermal state were removed: they are power-user
/// concepts that most people cannot act on, and each duplicated a rule that is
/// already here in plainer terms.
enum SystemAlertSignal: String, Codable, CaseIterable, Hashable {
    case diskAvailableCapacity
    case batteryService

    var metricID: MetricID {
        switch self {
        case .diskAvailableCapacity: return .disk
        case .batteryService: return .battery
        }
    }

    var unit: MetricUnit {
        switch self {
        case .diskAvailableCapacity: return .bytes
        case .batteryService: return .count
        }
    }

    var conditionKey: String { "system.\(rawValue)" }
}

struct SystemAlertRule: Codable, Equatable {
    var enabled: Bool
    var thresholdValue: Double
    var durationSeconds: Int
    var cooldownSeconds: Int
    var destinations: Set<AlertDestination>

    init(
        enabled: Bool,
        thresholdValue: Double,
        durationSeconds: Int = 30,
        cooldownSeconds: Int = 15 * 60,
        destinations: Set<AlertDestination> = [.attentionLog]
    ) {
        self.enabled = enabled
        self.thresholdValue = thresholdValue
        self.durationSeconds = durationSeconds
        self.cooldownSeconds = cooldownSeconds
        self.destinations = destinations
    }
}

struct SystemConditionReading: Equatable {
    let signal: SystemAlertSignal
    let value: Double

    init(_ signal: SystemAlertSignal, value: Double) {
        self.signal = signal
        self.value = value
    }
}

/// Evaluates native system signals independently of percentage-based module rules.
/// A missing reading means unavailable hardware or an unsupported provider value; it
/// never fabricates a healthy or failing state.
final class SystemConditionMonitor {
    typealias NotificationHandler = (
        SystemAlertSignal,
        SystemAlertRule,
        SystemConditionReading
    ) -> Void

    var onConditionUpdate: ((AlertConditionUpdate) -> Void)?

    private var lastFired: [SystemAlertSignal: Date] = [:]
    private var violationStartedAt: [SystemAlertSignal: Date] = [:]
    private var states: [SystemAlertSignal: AlertConditionState] = [:]
    private let notificationHandler: NotificationHandler

    init(notificationHandler: NotificationHandler? = nil) {
        self.notificationHandler = notificationHandler ?? Self.postNotification
    }

    func state(for signal: SystemAlertSignal) -> AlertConditionState {
        states[signal] ?? .normal
    }

    func evaluate(
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
                recoverIfNeeded(
                    signal: signal,
                    reading: reading,
                    rule: rule
                )
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

    static func isViolating(
        _ reading: SystemConditionReading,
        threshold: Double
    ) -> Bool {
        switch reading.signal {
        case .diskAvailableCapacity:
            return reading.value <= threshold
        case .batteryService:
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

    private static func postNotification(
        signal: SystemAlertSignal,
        rule: SystemAlertRule,
        reading: SystemConditionReading
    ) {
        let content = UNMutableNotificationContent()
        content.title = signal.notificationTitle
        content.body = signal.notificationBody(
            value: reading.value,
            threshold: rule.thresholdValue
        )
        content.sound = .default
        if let attachment = NotificationSymbolAttachment.make(for: signal.metricID) {
            content.attachments = [attachment]
        }
        let request = UNNotificationRequest(
            identifier: "mectrics.alert.\(signal.conditionKey)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}

private extension SystemAlertSignal {
    var notificationTitle: String {
        switch self {
        case .diskAvailableCapacity:
            return String(
                localized: "alert.system.diskCapacity.title",
                defaultValue: "Disk space is running low"
            )
        case .batteryService:
            return String(
                localized: "alert.system.batteryService.title",
                defaultValue: "Battery service is recommended"
            )
        }
    }

    func notificationBody(value: Double, threshold: Double) -> String {
        switch self {
        case .diskAvailableCapacity:
            return String(
                localized: "alert.system.diskCapacity.body",
                defaultValue: "\(MetricFormat.bytes(value)) remains, below your \(MetricFormat.bytes(threshold)) limit."
            )
        case .batteryService:
            return String(
                localized: "alert.system.batteryService.body",
                defaultValue: "macOS reports that the battery needs service."
            )
        }
    }
}
