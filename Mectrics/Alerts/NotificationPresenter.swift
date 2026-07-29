import AppKit
import MetricsKit
import UserNotifications

/// Presents Mectrics notifications as banners even while the app is frontmost, and
/// gives each one the symbol of the module it is about.
///
/// Without a delegate, macOS suppresses the banner whenever the app is active and
/// files the notification straight into Notification Center — which is exactly what
/// happens when someone sends a test from Settings, making the feature look broken.
@MainActor
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationPresenter()

    func install() {
        UNUserNotificationCenter.current().delegate = self
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler:
            @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}
