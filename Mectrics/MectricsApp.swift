import SwiftUI

/// Mectrics — a menu bar system monitor.
///
/// The app runs as an "accessory" (menu bar agent): there is no Dock icon and no main
/// window. Menu bar items are managed by `MenuBarController` inside `AppDelegate`. The
/// `Settings` scene here only provides the settings window.
@main
struct MectricsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(model: appDelegate.model)
        }
        .windowResizability(.contentSize)
    }
}
