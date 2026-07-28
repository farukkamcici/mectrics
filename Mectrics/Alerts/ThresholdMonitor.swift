import Foundation
import UserNotifications
import MetricsKit

/// One user-configurable alert rule per module. `thresholdPercent` compares against
/// the module's primary value (× 100). Battery alerts fire *below* the threshold,
/// every other module *above* it.
struct AlertRule: Codable, Equatable {
    var enabled: Bool
    var thresholdPercent: Int
}

/// Watches the latest samples and posts a local notification when a value crosses its
/// threshold. Fires only on the crossing (not continuously) and at most once per
/// cooldown window per module, so a pegged CPU doesn't spam the user.
/// Always called from the main thread (the engine's cycle callback).
final class ThresholdMonitor {
    private var lastFired: [MetricID: Date] = [:]
    private var wasViolating: [MetricID: Bool] = [:]
    private let cooldown: TimeInterval = 15 * 60

    private static var authorizationRequested = false

    /// Ask for notification permission once, the first time alerts are actually used.
    static func requestAuthorizationIfNeeded() {
        guard !authorizationRequested else { return }
        authorizationRequested = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func evaluate(latest: [MetricID: MetricSample], rules: [MetricID: AlertRule]) {
        for (id, rule) in rules where rule.enabled {
            guard let sample = latest[id] else { continue }
            // Sensors carry °C directly; everything else is a 0...1 fraction.
            let measured = sample.unit == .celsius ? sample.value : sample.value * 100
            let violating = Self.isBelowRule(id)
                ? measured <= Double(rule.thresholdPercent)
                : measured >= Double(rule.thresholdPercent)

            let crossed = violating && !(wasViolating[id] ?? false)
            wasViolating[id] = violating
            guard crossed else { continue }

            let now = Date()
            guard now.timeIntervalSince(lastFired[id] ?? .distantPast) >= cooldown else { continue }
            lastFired[id] = now
            post(for: id, rule: rule, measured: Int(measured.rounded()))
        }
    }

    /// Battery alerts when the value drops below the threshold; everything else above.
    static func isBelowRule(_ id: MetricID) -> Bool { id == .battery }

    private func post(for id: MetricID, rule: AlertRule, measured: Int) {
        Self.requestAuthorizationIfNeeded()

        let content = UNMutableNotificationContent()
        content.title = Self.title(for: id)
        if id == .sensors {
            content.body = String(localized: "alert.body.temp",
                defaultValue: "CPU temperature is \(measured)°C — above your \(rule.thresholdPercent)°C threshold.")
        } else {
            content.body = Self.isBelowRule(id)
                ? String(localized: "alert.body.below",
                         defaultValue: "\(id.localizedName) is at \(measured)% — below your \(rule.thresholdPercent)% threshold.")
                : String(localized: "alert.body.above",
                         defaultValue: "\(id.localizedName) is at \(measured)% — above your \(rule.thresholdPercent)% threshold.")
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
        case .battery: return String(localized: "alert.title.battery", defaultValue: "Low battery")
        case .disk:    return String(localized: "alert.title.disk", defaultValue: "Disk almost full")
        case .sensors: return String(localized: "alert.title.temp", defaultValue: "High CPU temperature")
        default:       return String(localized: "alert.title.high",
                                     defaultValue: "High \(id.localizedName) usage")
        }
    }
}
