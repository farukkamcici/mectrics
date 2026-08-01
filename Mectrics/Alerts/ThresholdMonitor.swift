import AppKit
import Foundation
import MetricsKit
import UserNotifications

enum AlertNotificationDelivery {
    static func threshold(
        for id: MetricID,
        rule: AlertRule,
        measured: Int
    ) {
        let content = UNMutableNotificationContent()
        content.title = thresholdTitle(for: id)
        if id == .sensors {
            content.body = String(
                localized: "alert.body.temp",
                defaultValue: "CPU temperature is \(measured)°C, above your \(rule.thresholdPercent)°C threshold."
            )
        } else {
            content.body = ThresholdMonitor.isBelowRule(id)
                ? String(
                    localized: "alert.body.below",
                    defaultValue: "\(id.localizedName) is at \(measured)%, below your \(rule.thresholdPercent)% threshold."
                )
                : String(
                    localized: "alert.body.above",
                    defaultValue: "\(id.localizedName) is at \(measured)%, above your \(rule.thresholdPercent)% threshold."
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

    static func systemCondition(
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
        let request = UNNotificationRequest(
            identifier: "mectrics.alert.\(signal.conditionKey)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private static func thresholdTitle(for id: MetricID) -> String {
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

private extension SystemAlertSignal {
    var notificationTitle: String {
        switch self {
        case .thermalPressure:
            return String(
                localized: "alert.system.thermal.title",
                defaultValue: "Your Mac is slowing down to cool off"
            )
        case .memoryPressure:
            return String(
                localized: "alert.system.memoryPressure.title",
                defaultValue: "Your Mac is short on memory"
            )
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
        case .thermalPressure:
            // Named for the whole chip: on Apple silicon this state covers the GPU
            // as well, and a person waiting on a render should know that.
            return String(
                localized: "alert.system.thermal.body",
                defaultValue: "macOS is limiting CPU and GPU performance to cool your Mac down. Slowdown is \(SystemSignalFormat.thermal(value))."
            )
        case .memoryPressure:
            return String(
                localized: "alert.system.memoryPressure.body",
                defaultValue: "Memory pressure reached \(SystemSignalFormat.pressure(value)). macOS is compressing and swapping to keep apps running."
            )
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
