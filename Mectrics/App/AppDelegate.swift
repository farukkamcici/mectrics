import AppKit
import MetricsKit

/// App lifecycle + menu bar setup.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var menuBar: MenuBarController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar agent: no Dock icon.
        NSApp.setActivationPolicy(.accessory)

        menuBar = MenuBarController(model: model)
        menuBar.rebuild()

        // Rebuild the menu bar when the module selection changes.
        model.onModulesChanged = { [weak self] in
            self?.menuBar.rebuild()
        }

        // Update the model and menu bar on every sampling cycle (main thread).
        model.engine.onCycle = { [weak self] updated in
            guard let self else { return }
            for (id, sample) in updated {
                self.model.latest[id] = sample
            }
            self.menuBar.refresh()
        }

        // Energy-friendly: sample more slowly on battery.
        let onBattery = Self.isOnBattery()
        model.engine.start(onBattery: onBattery)
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.engine.stop()
    }

    /// Are we currently on battery power? (Simple check for the initial interval.)
    private static func isOnBattery() -> Bool {
        guard let sample = BatteryProvider().sample() else { return false }
        return (sample.detail["charging"] ?? 0) == 0
    }
}
