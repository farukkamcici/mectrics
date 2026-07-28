import AppKit
import IOKit.ps
import MetricsKit

/// App lifecycle + menu bar setup.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var menuBar: MenuBarController!
    private var floatingPanel: FloatingPanelController!
    private var settings: SettingsWindowController!
    private var onboarding: OnboardingWindowController?
    private let thresholds = ThresholdMonitor()
    private let hotKey = GlobalHotKey()
    private let widgetSnapshots = WidgetSnapshotPublisher()
    private var powerSourceRunLoopSource: CFRunLoopSource?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Mectrics has a regular app lifecycle: it appears in the Dock and owns a
        // persistent settings window in addition to its menu bar surfaces.
        NSApp.setActivationPolicy(.regular)
        installMainMenu()

        menuBar = MenuBarController(model: model)
        menuBar.rebuild()

        // Rebuild the menu bar when the module selection changes.
        model.onModulesChanged = { [weak self] in
            self?.menuBar.rebuild()
            self?.floatingPanel.refreshSize()
            guard let self else { return }
            self.widgetSnapshots.publish(from: self.model, force: true)
        }

        // Floating panel (always-on-top live widget), restored from last session.
        floatingPanel = FloatingPanelController(model: model)
        model.onFloatingPanelChanged = { [weak self] visible in
            self?.floatingPanel.setVisible(visible)
        }
        if model.showFloatingPanel {
            floatingPanel.setVisible(true)
        }

        // Redraw immediately when a look-related setting (accent, panel layout,
        // icons) changes.
        model.onAppearanceChanged = { [weak self] in
            self?.menuBar.refresh()
            self?.floatingPanel.refreshSize()
        }

        // Settings window (manual controller — no SwiftUI Settings scene).
        settings = SettingsWindowController(model: model) { [weak self] in
            self?.updateActivationPolicyAfterClosingAWindow()
        }
        model.onOpenSettings = { [weak self] in
            self?.settings.show()
        }
        model.onOpenOnboarding = { [weak self] in
            self?.showOnboarding()
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
            showOnboarding()
        } else {
            settings.show()
        }

        // Update the model and menu bar on every sampling cycle (main thread).
        model.engine.onCycleReport = { [weak self] report in
            guard let self else { return }
            self.model.apply(report)
            self.model.historyRecorder.record(report.samples)
            self.menuBar.refresh()
            self.thresholds.evaluate(latest: self.model.latest, rules: self.model.alertRules)
            self.widgetSnapshots.publish(from: self.model)
        }

        // Energy-friendly: sample more slowly on battery.
        model.engine.start(onBattery: Self.isOnBattery())
        startMonitoringPowerSource()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let powerSourceRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSourceRunLoopSource, .defaultMode)
        }
        model.engine.stop()
        model.historyRecorder.checkpoint()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows flag: Bool) -> Bool {
        if let onboarding {
            onboarding.show()
        } else {
            settings.show()
        }
        return true
    }

    @objc private func showSettings(_ sender: Any?) {
        settings.show()
    }

    @objc private func showWelcome(_ sender: Any?) {
        showOnboarding()
    }

    @objc private func closeKeyWindow(_ sender: Any?) {
        NSApp.keyWindow?.performClose(sender)
    }

    private func showOnboarding() {
        if onboarding == nil {
            onboarding = OnboardingWindowController(model: model) { [weak self] in
                self?.onboarding = nil
                self?.updateActivationPolicyAfterClosingAWindow()
            }
        }
        onboarding?.show()
    }

    /// A menu bar app only needs a Dock presence while it owns a standard window.
    /// Deferring one run-loop pass lets AppKit finish removing the closing window.
    private func updateActivationPolicyAfterClosingAWindow() {
        DispatchQueue.main.async {
            let hasVisibleStandardWindow = NSApp.windows.contains { window in
                window.isVisible && !(window is NSPanel)
            }
            if !hasVisibleStandardWindow {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    /// Installs the standard Mac commands because this AppKit-only app has no
    /// SwiftUI scene to synthesize a main menu.
    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: String(
            localized: "menu.about",
            defaultValue: "About Mectrics"
        ), action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let settingsItem = appMenu.addItem(withTitle: String(
            localized: "menu.settings",
            defaultValue: "Settings…"
        ), action: #selector(showSettings(_:)), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: String(
            localized: "menu.hide",
            defaultValue: "Hide Mectrics"
        ), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: String(
            localized: "menu.quit",
            defaultValue: "Quit Mectrics"
        ), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: String(
            localized: "menu.window",
            defaultValue: "Window"
        ))
        let closeItem = windowMenu.addItem(withTitle: String(
            localized: "menu.close",
            defaultValue: "Close"
        ), action: #selector(closeKeyWindow(_:)), keyEquivalent: "w")
        closeItem.target = self
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        NSApp.windowsMenu = windowMenu

        let helpMenuItem = NSMenuItem()
        let helpMenu = NSMenu(title: String(
            localized: "menu.help",
            defaultValue: "Help"
        ))
        let welcomeItem = helpMenu.addItem(withTitle: String(
            localized: "menu.showWelcome",
            defaultValue: "Show Welcome"
        ), action: #selector(showWelcome(_:)), keyEquivalent: "")
        welcomeItem.target = self
        helpMenuItem.submenu = helpMenu
        mainMenu.addItem(helpMenuItem)
        NSApp.helpMenu = helpMenu

        NSApp.mainMenu = mainMenu
    }

    private func startMonitoringPowerSource() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let appDelegate = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async {
                appDelegate.model.engine.updatePowerState(onBattery: AppDelegate.isOnBattery())
            }
        }, context)?.takeRetainedValue() else { return }

        powerSourceRunLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
    }

    /// Uses the system's providing power source, not battery charging state. A fully
    /// charged Mac connected to AC therefore remains on the faster AC policy.
    private static func isOnBattery() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sourceType = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue()
        else { return false }
        return sourceType as String == kIOPSBatteryPowerValue
    }
}
