import AppKit
import Foundation
import UserNotifications
import MetricsKit

enum AlertDestination: String, Codable, CaseIterable, Hashable {
    case notification
    case compactHealth
    case attentionLog
}

enum AlertConditionState: String, Codable, Equatable {
    case normal
    case pending
    case active
}

enum AlertConditionTransition: Equatable {
    case pending
    case activated
    case recovered
}

struct AlertConditionUpdate: Equatable {
    let conditionKey: String
    let metricID: MetricID
    let state: AlertConditionState
    let transition: AlertConditionTransition
    let measuredValue: Double
    let unit: MetricUnit
    let thresholdValue: Double
    let durationSeconds: Int
    let startedAt: Date?
    let destinations: Set<AlertDestination>

    init(
        conditionKey: String? = nil,
        metricID: MetricID,
        state: AlertConditionState,
        transition: AlertConditionTransition,
        measuredValue: Double,
        unit: MetricUnit? = nil,
        thresholdValue: Double,
        durationSeconds: Int,
        startedAt: Date?,
        destinations: Set<AlertDestination>
    ) {
        self.conditionKey = conditionKey ?? "threshold.\(metricID.rawValue)"
        self.metricID = metricID
        self.state = state
        self.transition = transition
        self.measuredValue = measuredValue
        self.unit = unit ?? (metricID == .sensors ? .celsius : .percent)
        self.thresholdValue = thresholdValue
        self.durationSeconds = durationSeconds
        self.startedAt = startedAt
        self.destinations = destinations
    }
}

/// One user-configurable threshold rule per module. `thresholdPercent` compares
/// against the module's primary value (× 100). Battery fires below its threshold;
/// every other current percentage rule fires above it.
struct AlertRule: Codable, Equatable {
    var enabled: Bool
    var thresholdPercent: Int
    var durationSeconds: Int
    var cooldownSeconds: Int
    var destinations: Set<AlertDestination>

    init(
        enabled: Bool,
        thresholdPercent: Int,
        durationSeconds: Int = 30,
        cooldownSeconds: Int = 15 * 60,
        destinations: Set<AlertDestination> = [.attentionLog]
    ) {
        self.enabled = enabled
        self.thresholdPercent = thresholdPercent
        self.durationSeconds = durationSeconds
        self.cooldownSeconds = cooldownSeconds
        self.destinations = destinations
    }

    private enum CodingKeys: String, CodingKey {
        case enabled
        case thresholdPercent
        case durationSeconds
        case cooldownSeconds
        case destinations
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        thresholdPercent = try container.decode(Int.self, forKey: .thresholdPercent)
        durationSeconds = try container.decodeIfPresent(
            Int.self,
            forKey: .durationSeconds
        ) ?? 30
        cooldownSeconds = try container.decodeIfPresent(
            Int.self,
            forKey: .cooldownSeconds
        ) ?? 15 * 60

        if let decodedDestinations = try container.decodeIfPresent(
            Set<AlertDestination>.self,
            forKey: .destinations
        ) {
            destinations = decodedDestinations
        } else {
            // Legacy rules were implicitly notification-only. Preserve that choice
            // for enabled rules while giving every enabled rule a local lifecycle.
            destinations = enabled
                ? [.notification, .attentionLog]
                : [.attentionLog]
        }
    }
}

/// Evaluates alert rules as a small incident state machine. A continuous violation has
/// one identity from pending through recovery, regardless of how many destinations
/// display it.
final class ThresholdMonitor {
    typealias NotificationHandler = (MetricID, AlertRule, Int) -> Void

    var onConditionUpdate: ((AlertConditionUpdate) -> Void)?

    private static var authorizationRequested = false
    private var lastFired: [MetricID: Date] = [:]
    private var violationStartedAt: [MetricID: Date] = [:]
    private var states: [MetricID: AlertConditionState] = [:]
    private let notificationHandler: NotificationHandler

    init(notificationHandler: NotificationHandler? = nil) {
        self.notificationHandler = notificationHandler ?? Self.postNotification
    }

    /// Requests permission only after an explicit user action enables or tests
    /// notification delivery.
    static func requestAuthorizationIfNeeded() {
        guard !authorizationRequested else { return }
        authorizationRequested = true
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound]
        ) { _, _ in }
    }

    func state(for metricID: MetricID) -> AlertConditionState {
        states[metricID] ?? .normal
    }

    func evaluate(
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
        let inactiveIDs = Set(states.keys).subtracting(enabledIDs)
        for id in inactiveIDs {
            violationStartedAt[id] = nil
            states[id] = .normal
        }
    }

    /// Battery alerts when the value drops below the threshold; everything else above.
    static func isBelowRule(_ id: MetricID) -> Bool { id == .battery }

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

    private static func postNotification(
        for id: MetricID,
        rule: AlertRule,
        measured: Int
    ) {
        let content = UNMutableNotificationContent()
        content.title = title(for: id)
        if id == .sensors {
            content.body = String(
                localized: "alert.body.temp",
                defaultValue: "CPU temperature is \(measured)°C — above your \(rule.thresholdPercent)°C threshold."
            )
        } else {
            content.body = isBelowRule(id)
                ? String(
                    localized: "alert.body.below",
                    defaultValue: "\(id.localizedName) is at \(measured)% — below your \(rule.thresholdPercent)% threshold."
                )
                : String(
                    localized: "alert.body.above",
                    defaultValue: "\(id.localizedName) is at \(measured)% — above your \(rule.thresholdPercent)% threshold."
                )
        }
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "mectrics.alert.\(id.rawValue)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private static func title(for id: MetricID) -> String {
        switch id {
        case .battery:
            return String(localized: "alert.title.battery", defaultValue: "Low battery")
        case .disk:
            return String(localized: "alert.title.disk", defaultValue: "Disk almost full")
        case .sensors:
            return String(localized: "alert.title.temp", defaultValue: "High CPU temperature")
        default:
            return String(
                localized: "alert.title.high",
                defaultValue: "High \(id.localizedName) usage"
            )
        }
    }
}

enum NotificationAccessState: Equatable {
    case unknown
    case notDetermined
    case authorized
    case denied
    case deliveryDisabled
}

enum NotificationPermissionManager {
    static func current(
        completion: @escaping @Sendable (NotificationAccessState) -> Void
    ) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            completion(accessState(from: settings))
        }
    }

    static func request(
        completion: @escaping @Sendable (NotificationAccessState) -> Void
    ) {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound]
        ) { _, _ in
            current(completion: completion)
        }
    }

    static func sendTest(
        completion: @escaping @Sendable (NotificationAccessState) -> Void
    ) {
        current { state in
            switch state {
            case .notDetermined:
                request { requestedState in
                    if requestedState == .authorized {
                        deliverTest(completion: completion)
                    } else {
                        completion(requestedState)
                    }
                }
            case .authorized:
                deliverTest(completion: completion)
            case .unknown, .denied, .deliveryDisabled:
                completion(state)
            }
        }
    }

    /// Opens Notification settings, preferring this app's own row.
    ///
    /// The per-app query parameter and the pane identifier have both changed across
    /// macOS releases, so each candidate is tried in turn rather than assuming one
    /// works — a button that silently does nothing is worse than a less specific
    /// destination.
    @MainActor
    @discardableResult
    static func openSystemSettings() -> Bool {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.mectrics.app"
        let candidates = [
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(bundleID)",
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.notifications"
        ]
        for candidate in candidates {
            if let url = URL(string: candidate),
               NSWorkspace.shared.open(url) {
                return true
            }
        }
        return false
    }

    private static func accessState(
        from settings: UNNotificationSettings
    ) -> NotificationAccessState {
        switch settings.authorizationStatus {
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .authorized, .provisional, .ephemeral:
            return settings.alertSetting == .enabled
                ? .authorized
                : .deliveryDisabled
        @unknown default:
            return .unknown
        }
    }

    private static func deliverTest(
        completion: @escaping @Sendable (NotificationAccessState) -> Void
    ) {
        let content = UNMutableNotificationContent()
        content.title = String(
            localized: "alert.test.title",
            defaultValue: "Mectrics Test Notification"
        )
        content.body = String(
            localized: "alert.test.body",
            defaultValue: "Notifications are ready. This test did not create an attention event."
        )
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "mectrics.alert.test",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            completion(error == nil ? .authorized : .unknown)
        }
    }
}
