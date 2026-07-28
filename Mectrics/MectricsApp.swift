import AppKit

/// Mectrics — a system monitor with regular windows and menu bar indicators.
///
/// The app boots into AppKit without SwiftUI scenes. Menu bar items are managed by
/// `MenuBarController`, while settings, onboarding, and the floating panel are owned
/// by their respective controllers inside `AppDelegate`.
@main
@MainActor
enum MectricsMain {
    // NSApplication.delegate is unretained — keep the delegate alive here.
    private static let delegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.delegate = delegate
        app.run()
    }
}
