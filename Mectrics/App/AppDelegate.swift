import AppKit
import MetricsKit

/// App lifecycle + menu bar setup.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var menuBar: MenuBarController!
    private var floatingPanel: FloatingPanelController!
    private var onboarding: OnboardingWindowController?
    private let thresholds = ThresholdMonitor()
    private let hotKey = GlobalHotKey()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar agent: no Dock icon.
        NSApp.setActivationPolicy(.accessory)

        menuBar = MenuBarController(model: model)
        menuBar.rebuild()

        // Rebuild the menu bar when the module selection changes.
        model.onModulesChanged = { [weak self] in
            self?.menuBar.rebuild()
        }

        // Floating panel (always-on-top live widget), restored from last session.
        floatingPanel = FloatingPanelController(model: model)
        model.onFloatingPanelChanged = { [weak self] visible in
            self?.floatingPanel.setVisible(visible)
        }
        if model.showFloatingPanel {
            floatingPanel.setVisible(true)
        }

        // Redraw immediately when a look-related setting (accent, density) changes.
        model.onAppearanceChanged = { [weak self] in
            self?.menuBar.refresh()
        }

        // Global hotkey (⌃⌥M) toggles the floating panel from anywhere.
        hotKey.onPressed = { [weak self] in
            self?.model.showFloatingPanel.toggle()
        }
        hotKey.register()

        // If the user already enabled alerts, get the permission prompt out of the way.
        if model.alertRules.values.contains(where: \.enabled) {
            ThresholdMonitor.requestAuthorizationIfNeeded()
        }

        // First launch: walk through the onboarding once.
        if !model.hasCompletedOnboarding {
            onboarding = OnboardingWindowController(model: model)
            onboarding?.show()
        }

        // Update the model and menu bar on every sampling cycle (main thread).
        model.engine.onCycle = { [weak self] updated in
            guard let self else { return }
            for (id, sample) in updated {
                self.model.latest[id] = sample
            }
            self.menuBar.refresh()
            self.thresholds.evaluate(latest: self.model.latest, rules: self.model.alertRules)
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
