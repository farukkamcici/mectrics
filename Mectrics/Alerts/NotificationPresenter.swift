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

/// Renders the module symbol that rides along with a notification.
///
/// Separate from the presenter because notifications are posted from the sampling
/// path rather than from an actor-isolated context.
enum NotificationSymbolAttachment {
    /// A rendered module symbol, attached so the notification shows which metric it
    /// came from next to the app icon.
    ///
    /// Symbols are template images, which would render as invisible black on the
    /// notification's own background, so the glyph is drawn into an opaque tile at a
    /// fixed tint instead.
    static func make(for id: MetricID) -> UNNotificationAttachment? {
        let side: CGFloat = 128
        guard let symbol = NSImage(
            systemSymbolName: MetricSymbol.name(for: id),
            accessibilityDescription: nil
        )?.withSymbolConfiguration(
            .init(pointSize: side * 0.5, weight: .medium)
        ) else {
            return nil
        }

        let canvas = NSImage(size: NSSize(width: side, height: side))
        canvas.lockFocus()
        NSColor.systemBlue.setFill()
        NSBezierPath(
            roundedRect: NSRect(x: 0, y: 0, width: side, height: side),
            xRadius: side * 0.22,
            yRadius: side * 0.22
        ).fill()
        let size = symbol.size
        let origin = NSPoint(
            x: (side - size.width) / 2,
            y: (side - size.height) / 2
        )
        symbol.draw(
            at: origin,
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        NSColor.white.set()
        NSRect(origin: origin, size: size).fill(using: .sourceAtop)
        canvas.unlockFocus()

        guard let tiff = canvas.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else {
            return nil
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mectrics-\(id.rawValue)-\(UUID().uuidString).png")
        do {
            try png.write(to: url, options: .atomic)
            return try UNNotificationAttachment(
                identifier: "mectrics.symbol.\(id.rawValue)",
                url: url,
                options: nil
            )
        } catch {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
    }
}
