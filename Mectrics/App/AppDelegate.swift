import AppKit
import IOKit.ps
import MetricsKit

enum StartupPresentation: Equatable {
    case onboarding
    case routes
    case none
}

enum StartupPresentationPolicy {
    static func presentation(
        hasCompletedOnboarding: Bool,
        hasPendingRoutes: Bool
    ) -> StartupPresentation {
        if !hasCompletedOnboarding {
            return .onboarding
        }
        if hasPendingRoutes {
            return .routes
        }
        return .none
    }
}

/// App lifecycle + menu bar setup.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let lastPresentedWhatsNewVersionKey = "lastPresentedWhatsNewVersion"

    let model = AppModel()
    private var menuBar: MenuBarController!
    private var floatingPanel: FloatingPanelController!
    private var settings: SettingsWindowController!
    private var metricDetail: MetricDetailWindowController!
    private var attentionLog: AttentionLogWindowController!
    private var diagnostics: DiagnosticsWindowController!
    private var aboutWindow: AboutWindowController!
    private var whatsNewWindow: WhatsNewWindowController!
    private let updates = UpdateController()
    private var onboarding: OnboardingWindowController?
    private let thresholds = ThresholdMonitor()
    private let systemConditions = SystemConditionMonitor()
    private var energyGuard: EnergyGuardController!
    private let hotKey = GlobalHotKey()
    private let widgetSnapshots = WidgetSnapshotPublisher()
    private var powerSourceRunLoopSource: CFRunLoopSource?
    private var pendingRoutes: [ApplicationRoute] = []
    private var isReadyForRoutes = false
    private var visibleDetailMetricIDs: Set<MetricID> = []

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Keep cold starts silent after onboarding. Window controllers promote the
        // app to a regular Dock application only in response to an explicit action.
        NSApp.setActivationPolicy(.accessory)
        installMainMenu()
        DiagnosticLogStore.shared.record(.appLaunched)

        menuBar = MenuBarController(model: model)
        menuBar.rebuild()
        energyGuard = EnergyGuardController(model: model)
        menuBar.onDetailVisibilityChanged = { [weak self] id, visible in
            self?.setDetail(id, visible: visible)
        }

        // Rebuild the menu bar when the module selection changes.
        model.onModulesChanged = { [weak self] in
            self?.menuBar.rebuild()
            self?.floatingPanel.refreshSize()
            guard let self else { return }
            self.widgetSnapshots.publish(from: self.model, force: true)
            self.refreshEnergyGuardVisibility()
        }

        // Floating panel (always-on-top live widget), restored from last session.
        floatingPanel = FloatingPanelController(model: model)
        model.onFloatingPanelChanged = { [weak self] visible in
            self?.floatingPanel.setVisible(visible)
            self?.refreshEnergyGuardVisibility()
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
        metricDetail = MetricDetailWindowController(
            model: model,
            onClose: { [weak self] in
                self?.updateActivationPolicyAfterClosingAWindow()
            },
            onVisibilityChanged: { [weak self] id, visible in
                self?.setDetail(id, visible: visible)
            }
        )
        attentionLog = AttentionLogWindowController(
            store: model.attentionLog
        ) { [weak self] in
            self?.updateActivationPolicyAfterClosingAWindow()
        }
        diagnostics = DiagnosticsWindowController(
            model: model
        ) { [weak self] in
            self?.updateActivationPolicyAfterClosingAWindow()
        }
        aboutWindow = AboutWindowController { [weak self] in
            self?.updateActivationPolicyAfterClosingAWindow()
        }
        whatsNewWindow = WhatsNewWindowController { [weak self] in
            self?.updateActivationPolicyAfterClosingAWindow()
        }
        model.onOpenSettings = { [weak self] in
            self?.settings.show()
        }
        model.onOpenOnboarding = { [weak self] in
            self?.showOnboarding()
        }
        model.onOpenAttentionLog = { [weak self] in
            self?.attentionLog.show()
        }
        model.onOpenDiagnostics = { [weak self] in
            self?.diagnostics.show()
        }
        model.onOpenMetricDetail = { [weak self] metricID in
            self?.metricDetail.show(metricID: metricID)
        }
        model.onEnergyGuardPreferenceChanged = { [weak self] in
            self?.energyGuard.preferenceChanged()
        }

        // Global hotkey (⌃⌥M) toggles the floating panel from anywhere.
        hotKey.onPressed = { [weak self] in
            self?.model.showFloatingPanel.toggle()
        }
        hotKey.register()

        thresholds.onConditionUpdate = { [weak self] update in
            self?.model.attentionLog.apply(update)
            self?.model.applyAlertUpdate(update)
        }
        systemConditions.onConditionUpdate = { [weak self] update in
            self?.model.attentionLog.apply(update)
            self?.model.applyAlertUpdate(update)
        }

        initializeWhatsNewBaselineIfNeeded()

        switch StartupPresentationPolicy.presentation(
            hasCompletedOnboarding: model.hasCompletedOnboarding,
            hasPendingRoutes: !pendingRoutes.isEmpty
        ) {
        case .onboarding:
            showOnboarding()
        case .routes, .none:
            break
        }

        // Update the model and menu bar on every sampling cycle (main thread).
        model.engine.onCycleReport = { [weak self] report in
            guard let self else { return }
            self.model.apply(report)
            self.model.historyRecorder.record(report.samples)
            self.menuBar.refresh()
            self.thresholds.evaluate(latest: self.model.latest, rules: self.model.alertRules)
            self.systemConditions.evaluate(
                readings: self.model.systemConditionReadings,
                rules: self.model.systemAlertRules
            )
            self.widgetSnapshots.publish(from: self.model)
        }

        // Energy-friendly: sample more slowly on battery.
        let onBattery = Self.isOnBattery()
        model.engine.start(onBattery: onBattery)
        DiagnosticLogStore.shared.record(.samplingStarted)
        energyGuard.start(onBattery: onBattery)
        refreshEnergyGuardVisibility()
        startMonitoringPowerSource()

        isReadyForRoutes = true
        let routes = pendingRoutes
        pendingRoutes.removeAll()
        for route in routes {
            open(route)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSAppleEventManager.shared().removeEventHandler(
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
        if let powerSourceRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSourceRunLoopSource, .defaultMode)
        }
        model.engine.stop()
        energyGuard.stop()
        model.historyRecorder.checkpoint()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows flag: Bool) -> Bool {
        if let onboarding {
            onboarding.show()
        } else if presentWhatsNewAfterUpgradeIfNeeded() {
            return true
        } else {
            settings.show()
        }
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            receive(url)
        }
    }

    @objc private func handleGetURLEvent(
        _ event: NSAppleEventDescriptor,
        withReplyEvent replyEvent: NSAppleEventDescriptor
    ) {
        guard let rawURL = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: rawURL)
        else {
            return
        }
        receive(url)
    }

    @objc private func showSettings(_ sender: Any?) {
        settings.show()
    }

    @objc private func showWelcome(_ sender: Any?) {
        showOnboarding()
    }

    @objc private func showAbout(_ sender: Any?) {
        aboutWindow.show()
    }

    @objc private func showWhatsNew(_ sender: Any?) {
        markCurrentWhatsNewVersionPresented()
        whatsNewWindow.show()
    }

    @objc private func showDiagnostics(_ sender: Any?) {
        diagnostics.show()
    }

    @objc private func closeKeyWindow(_ sender: Any?) {
        NSApp.keyWindow?.performClose(sender)
    }

    private func open(_ route: ApplicationRoute) {
        switch route {
        case .overview:
            settings.show(pane: .general)
        case .metric(let metricID):
            metricDetail.show(metricID: metricID)
        case .alerts:
            settings.show(pane: .alerts)
        case .attentionLog:
            attentionLog.show()
        case .about:
            aboutWindow.show()
        case .whatsNew:
            markCurrentWhatsNewVersionPresented()
            whatsNewWindow.show()
        case .diagnostics:
            diagnostics.show()
        }
    }

    private func receive(_ url: URL) {
        guard let route = ApplicationRoute(url: url) else { return }
        if isReadyForRoutes {
            open(route)
        } else if !pendingRoutes.contains(route) {
            pendingRoutes.append(route)
        }
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

    private var currentMarketingVersion: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "0"
    }

    private func initializeWhatsNewBaselineIfNeeded() {
        let defaults = UserDefaults.standard
        if defaults.string(forKey: Self.lastPresentedWhatsNewVersionKey) == nil {
            defaults.set(
                currentMarketingVersion,
                forKey: Self.lastPresentedWhatsNewVersionKey
            )
        }
    }

    private func markCurrentWhatsNewVersionPresented() {
        UserDefaults.standard.set(
            currentMarketingVersion,
            forKey: Self.lastPresentedWhatsNewVersionKey
        )
    }

    @discardableResult
    private func presentWhatsNewAfterUpgradeIfNeeded() -> Bool {
        let storedVersion = UserDefaults.standard.string(
            forKey: Self.lastPresentedWhatsNewVersionKey
        )
        guard WhatsNewPolicy.shouldPresent(
            currentVersion: currentMarketingVersion,
            storedVersion: storedVersion
        ) else {
            return false
        }
        markCurrentWhatsNewVersionPresented()
        whatsNewWindow.show()
        return true
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
        let aboutItem = appMenu.addItem(withTitle: String(
            localized: "menu.about",
            defaultValue: "About Mectrics"
        ), action: #selector(showAbout(_:)), keyEquivalent: "")
        aboutItem.target = self
        appMenu.addItem(.separator())
        let settingsItem = appMenu.addItem(withTitle: String(
            localized: "menu.settings",
            defaultValue: "Settings…"
        ), action: #selector(showSettings(_:)), keyEquivalent: ",")
        settingsItem.target = self
        let updateItem = appMenu.addItem(withTitle: String(
            localized: "menu.checkForUpdates",
            defaultValue: "Check for Updates…"
        ), action: #selector(UpdateController.checkForUpdates(_:)), keyEquivalent: "")
        updateItem.target = updates
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
        let whatsNewItem = helpMenu.addItem(withTitle: String(
            localized: "menu.whatsNew",
            defaultValue: "What’s New in Mectrics"
        ), action: #selector(showWhatsNew(_:)), keyEquivalent: "")
        whatsNewItem.target = self
        let diagnosticsItem = helpMenu.addItem(withTitle: String(
            localized: "menu.diagnostics",
            defaultValue: "Mectrics Diagnostics…"
        ), action: #selector(showDiagnostics(_:)), keyEquivalent: "")
        diagnosticsItem.target = self
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
                let onBattery = AppDelegate.isOnBattery()
                appDelegate.model.engine.updatePowerState(
                    onBattery: onBattery
                )
                appDelegate.energyGuard.updatePowerSource(
                    onBattery: onBattery
                )
                DiagnosticLogStore.shared.record(.powerSourceChanged)
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

    private func setDetail(_ id: MetricID, visible: Bool) {
        if visible {
            visibleDetailMetricIDs.insert(id)
        } else {
            visibleDetailMetricIDs.remove(id)
        }
        refreshEnergyGuardVisibility()
    }

    private func refreshEnergyGuardVisibility() {
        var visible = Set<MetricID>()
        for id in visibleDetailMetricIDs {
            switch id {
            case .cpu:
                visible.insert(.sensors)
            case .gpu:
                visible.formUnion([.gpu, .sensors])
            case .sensors, .bluetooth, .fans:
                visible.insert(id)
            default:
                break
            }
        }
        if model.showFloatingPanel {
            visible.formUnion(
                model.enabledModules.intersection([
                    .gpu, .bluetooth, .fans
                ])
            )
        }
        energyGuard?.updateVisibleHeavyMetrics(visible)
    }
}
