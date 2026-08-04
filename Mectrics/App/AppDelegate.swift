import AppKit
import MetricsKit

enum StartupPresentation: Equatable {
    case onboarding
    case routes
    case whatsNew
    case none
}

enum UpdatePermissionPolicy {
    /// Whether this launch should ask about automatic update checks.
    ///
    /// Only on a quiet launch. Someone who just walked through onboarding has already
    /// answered it there, and someone reading release notes has just been talked to —
    /// stacking a second question on either is how an app becomes tiresome. It waits
    /// for a launch where Mectrics has nothing else to say, and it is asked once.
    /// `isRunningTests` is not a detail. The XCTest host launches the real app, so a
    /// modal question at startup blocks the test run forever rather than failing it,
    /// which is how this was found.
    static func shouldAsk(
        presentation: StartupPresentation,
        hasAnswered: Bool,
        isRunningTests: Bool = Self.isRunningTests
    ) -> Bool {
        guard !isRunningTests else { return false }
        return presentation == .none && !hasAnswered
    }

    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}

enum StartupPresentationPolicy {
    /// What a launch should put on screen, in order of who asked for it.
    ///
    /// Someone arriving for the first time gets onboarding. Someone who opened a
    /// `mectrics://` link named a destination, and that beats anything Mectrics wants
    /// to say on its own. An upgrade is last: it is the app's news, not the user's
    /// errand.
    ///
    /// What's New belongs on this path and not only on reopen. Sparkle installs an
    /// update by quitting the app and starting it again, which is a launch — so
    /// handling the upgrade only in `applicationShouldHandleReopen` meant the window
    /// never appeared at the one moment it exists for. A menu bar agent has no Dock
    /// icon to click, so reopen almost never fires at all.
    static func presentation(
        hasCompletedOnboarding: Bool,
        hasPendingRoutes: Bool,
        hasUpgraded: Bool = false
    ) -> StartupPresentation {
        if !hasCompletedOnboarding {
            return .onboarding
        }
        if hasPendingRoutes {
            return .routes
        }
        if hasUpgraded {
            return .whatsNew
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
    private var settings: SettingsWindowController!
    private var metricDetail: MetricDetailWindowController!
    private var attentionLog: AttentionLogWindowController!
    private var diagnostics: DiagnosticsWindowController!
    private var aboutWindow: AboutWindowController!
    private var whatsNewWindow: WhatsNewWindowController!
    private let updates = UpdateController()
    private var onboarding: OnboardingWindowController?
    private let thresholds = ThresholdMonitor(
        notificationHandler: AlertNotificationDelivery.threshold
    )
    private let systemConditions = SystemConditionMonitor(
        notificationHandler: AlertNotificationDelivery.systemCondition
    )
    private var energyGuard: EnergyGuardController!
    private let widgetSnapshots = WidgetSnapshotPublisher()
    private let dock = DockPresence()
    private var powerSourceRunLoopSource: CFRunLoopSource?
    private var pendingRoutes: [ApplicationRoute] = []
    private var isReadyForRoutes = false
    private var visibleDetailMetricIDs: Set<MetricID> = []
    private var hasRecordedFirstSample = false

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
        // Must be set before any notification is delivered, or macOS suppresses the
        // banner whenever Mectrics is the active app.
        NotificationPresenter.shared.install()
        DiagnosticLogStore.shared.record(.appLaunched)

        menuBar = MenuBarController(model: model)
        menuBar.rebuild()
        PerformanceSignposts.menuBarReady()
        energyGuard = EnergyGuardController(model: model)
        menuBar.onDetailVisibilityChanged = { [weak self] id, visible in
            self?.setDetail(id, visible: visible)
        }

        // Rebuild the menu bar when the module selection changes.
        model.onModulesChanged = { [weak self] in
            self?.menuBar.rebuild()
            guard let self else { return }
            self.widgetSnapshots.publish(from: self.model, force: true)
            self.refreshEnergyGuardVisibility()
        }

        // Redraw immediately when a look-related setting (accent, icons) changes.
        model.onAppearanceChanged = { [weak self] in
            self?.menuBar.refresh()
        }

        // Settings window (manual controller — no SwiftUI Settings scene).
        settings = SettingsWindowController(model: model, dock: dock)
        metricDetail = MetricDetailWindowController(
            model: model,
            dock: dock,
            onVisibilityChanged: { [weak self] id, visible in
                self?.setDetail(id, visible: visible)
            }
        )
        attentionLog = AttentionLogWindowController(
            store: model.attentionLog,
            dock: dock
        )
        diagnostics = DiagnosticsWindowController(model: model, dock: dock)
        aboutWindow = AboutWindowController(dock: dock)
        whatsNewWindow = WhatsNewWindowController(dock: dock)
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
        model.onCheckForUpdates = { [weak self] in
            self?.updates.checkForUpdates(nil)
        }
        model.onAutomaticUpdateChecksChanged = { [weak self] enabled in
            self?.updates.checksAutomatically = enabled
        }
        model.onEnergyGuardPreferenceChanged = { [weak self] in
            self?.energyGuard.preferenceChanged()
        }

        thresholds.onConditionUpdate = { [weak self] update in
            self?.model.attentionLog.apply(update)
            self?.model.applyAlertUpdate(update)
        }
        systemConditions.onConditionUpdate = { [weak self] update in
            self?.model.attentionLog.apply(update)
            self?.model.applyAlertUpdate(update)
        }

        initializeWhatsNewBaselineIfNeeded()

        let presentation = StartupPresentationPolicy.presentation(
            hasCompletedOnboarding: model.hasCompletedOnboarding,
            hasPendingRoutes: !pendingRoutes.isEmpty,
            hasUpgraded: hasUnpresentedUpgrade
        )
        switch presentation {
        case .onboarding:
            showOnboarding()
        case .whatsNew:
            presentWhatsNewAfterUpgradeIfNeeded()
        case .routes, .none:
            break
        }
        if UpdatePermissionPolicy.shouldAsk(
            presentation: presentation,
            hasAnswered: model.hasAnsweredUpdateChecks
        ) {
            askAboutAutomaticUpdateChecks()
        }

        // Update the model and menu bar on every sampling cycle (main thread).
        model.engine.onCycleReport = { [weak self] report in
            guard let self else { return }
            self.model.apply(report)
            self.menuBar.refresh()
            self.thresholds.evaluate(latest: self.model.latest, rules: self.model.alertRules)
            self.systemConditions.evaluate(
                readings: self.model.systemConditionReadings,
                rules: self.model.systemAlertRules
            )
            self.widgetSnapshots.publish(from: self.model)
            if !self.hasRecordedFirstSample && !report.samples.isEmpty {
                self.hasRecordedFirstSample = true
                PerformanceSignposts.firstSample(
                    metricCount: report.samples.count
                )
            }
        }

        // Energy-friendly: sample more slowly on battery.
        let onBattery = Self.isOnBattery()
        model.engine.start(onBattery: onBattery)
        PerformanceSignposts.engineStarted()
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
        case .menuBar:
            settings.show(pane: .menuBar)
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

    /// The one time Mectrics asks to use the network on its own.
    ///
    /// Existing users never saw the onboarding question, and leaving them on an old
    /// build is how a fix reaches nobody. Both answers are recorded, so this is asked
    /// once, and the choice stays changeable in Settings.
    private func askAboutAutomaticUpdateChecks() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let alert = NSAlert()
            alert.messageText = String(
                localized: "updates.ask.title",
                defaultValue: "Check for updates automatically?"
            )
            alert.informativeText = String(
                localized: "updates.ask.message",
                defaultValue: "Mectrics can ask the update server whether a newer version exists. The request says nothing about you or your Mac, an update is never installed on its own, and you can change this later in Settings."
            )
            alert.addButton(withTitle: String(
                localized: "updates.ask.enable",
                defaultValue: "Check Automatically"
            ))
            alert.addButton(withTitle: String(
                localized: "updates.ask.decline",
                defaultValue: "Not Now"
            ))
            NSApp.activate(ignoringOtherApps: true)
            let enabled = alert.runModal() == .alertFirstButtonReturn
            self.model.automaticUpdateChecks = enabled
            // A declined question is still an answered one.
            self.model.hasAnsweredUpdateChecks = true
        }
    }

    private func showOnboarding() {
        if onboarding == nil {
            onboarding = OnboardingWindowController(
                model: model,
                dock: dock
            ) { [weak self] in
                self?.onboarding = nil
            }
        }
        onboarding?.show()
    }

    private var currentMarketingVersion: String { Bundle.main.marketingVersion }

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

    /// True when this build is newer than the one whose notes were last shown. Read
    /// after `initializeWhatsNewBaselineIfNeeded`, so a fresh install is never treated
    /// as an upgrade.
    private var hasUnpresentedUpgrade: Bool {
        WhatsNewPolicy.shouldPresent(
            currentVersion: currentMarketingVersion,
            storedVersion: UserDefaults.standard.string(
                forKey: Self.lastPresentedWhatsNewVersionKey
            ),
            hasNotes: !ReleaseHighlights.current.isEmpty
        )
    }

    @discardableResult
    private func presentWhatsNewAfterUpgradeIfNeeded() -> Bool {
        let storedVersion = UserDefaults.standard.string(
            forKey: Self.lastPresentedWhatsNewVersionKey
        )
        guard WhatsNewPolicy.shouldPresent(
            currentVersion: currentMarketingVersion,
            storedVersion: storedVersion,
            hasNotes: !ReleaseHighlights.current.isEmpty
        ) else {
            return false
        }
        markCurrentWhatsNewVersionPresented()
        whatsNewWindow.show()
        return true
    }

    // The Dock icon follows `DockPresence`, which the window controllers report to
    // directly. Scanning `NSApp.windows` cannot answer the question: it also contains
    // the window behind every status item, so the app looked like it always had a
    // window open and the icon never went away after Settings was closed.

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
        SystemPowerSource.isOnBattery
    }

    private func setDetail(_ id: MetricID, visible: Bool) {
        if visible {
            visibleDetailMetricIDs.insert(id)
        } else {
            visibleDetailMetricIDs.remove(id)
        }
        // A popover or detail window is where a temperature is read, so it decides
        // whether the SMC is sampled at all as well as how often.
        model.setDetailVisible(id, visible)
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
            case .sensors, .fans:
                visible.insert(id)
            default:
                break
            }
        }
        energyGuard?.updateVisibleHeavyMetrics(visible)
    }
}
