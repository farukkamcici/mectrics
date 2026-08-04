import SwiftUI
import MetricsKit

/// General preferences tab of the settings window. Tabs are hosted individually by
/// `SettingsWindowController`, which owns the per-tab window sizes.
struct GeneralSettingsTab: View {
    @Bindable var model: AppModel
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var selectedLanguage = AppLanguage.selected()
    @State private var showUninstallConfirmation = false
    @State private var uninstallFailed = false
    @State private var relaunchFailed = false

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        LoginItem.setEnabled(newValue)
                    }
            } header: {
                Text("Startup")
            } footer: {
                Text("Mectrics has no Dock icon or window of its own; it lives in the menu bar.")
            }

            Section {
                Picker("Application", selection: $selectedLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.localizedName).tag(language)
                    }
                }
                .onChange(of: selectedLanguage) { _, newValue in
                    AppLanguage.apply(newValue)
                }

                if selectedLanguage != AppLanguage.selectionAtLaunch {
                    Button("Relaunch Mectrics") {
                        if !AppRelauncher.relaunch() {
                            relaunchFailed = true
                        }
                    }
                }
            } header: {
                Text("Language")
            } footer: {
                if selectedLanguage != AppLanguage.selectionAtLaunch {
                    Text("Relaunch Mectrics to apply the selected language.")
                }
            }

            Section {
                Toggle(
                    "Ease off when on battery or hot",
                    isOn: $model.adaptMonitoringToEnergyState
                )
                if model.adaptMonitoringToEnergyState {
                    LabeledContent("Right now") {
                        Text(
                            String(
                                localized: "energyGuard.currently",
                                defaultValue: "\(model.energyGuardMode.localizedName) · \(model.energyGuardReason.localizedName)"
                            )
                        )
                        .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Energy")
            } footer: {
                Text("Sensor and GPU readings use more resources, so they are taken less often on battery, in Low Power Mode, or when your Mac runs hot. Your alerts keep their timing either way.")
            }

            Section {
                LabeledContent("Version", value: Self.versionString)
                Toggle(isOn: $model.automaticUpdateChecks) {
                    Text("Check for updates automatically")
                    Text("Asks whether a newer version exists. Nothing about you or your Mac is sent.")
                }
                Button("Check for Updates…") {
                    model.onCheckForUpdates?()
                }
            } header: {
                Text("Updates")
            } footer: {
                Text("An update is never downloaded or installed on its own, and nothing that fails its signature check is installed at all. With automatic checks off, Mectrics reaches the network only when you press the button.")
            }

            Section {
                LabeledContent {
                    Button("Open") { model.onOpenAttentionLog?() }
                } label: {
                    Text("Attention Log")
                    Text("What needed attention and when, kept on this Mac")
                }
                LabeledContent {
                    Button("Open…") { model.onOpenDiagnostics?() }
                } label: {
                    Text("Diagnostics")
                    Text("Preview and save a support file, with identifiers removed")
                }
            } header: {
                Text("Privacy")
            } footer: {
                Label("Your readings never leave this Mac. Mectrics has no telemetry.",
                      systemImage: "lock.shield")
            }

            Section {
                LabeledContent {
                    Button("Uninstall…", role: .destructive) {
                        showUninstallConfirmation = true
                    }
                } label: {
                    Text("Remove Mectrics")
                    Text("Deletes the app, settings, and local history stored on this Mac")
                }
            } footer: {
                Text("macOS may retain the widget’s protected cache after removal and reclaims it once the extension is gone.")
            }
        }
        .formStyle(.grouped)
        // The toggle can be flipped elsewhere (onboarding); re-read on every appearance.
        .onAppear {
            launchAtLogin = LoginItem.isEnabled
            selectedLanguage = AppLanguage.selected()
        }
        .confirmationDialog(
            Text("Remove Mectrics and its local data?"),
            isPresented: $showUninstallConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove Mectrics", role: .destructive) {
                let cliState = CLIInstaller.installationState()
                if (cliState == .installed || cliState == .repairable),
                   CLIInstaller.remove() != .success {
                    uninstallFailed = true
                    return
                }
                if !Uninstaller.performUninstall() {
                    uninstallFailed = true
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Mectrics will quit and then delete itself, its settings, your alert rules, and the Attention Log. This cannot be undone.")
        }
        .alert(
            Text("Mectrics could not remove itself."),
            isPresented: $uninstallFailed
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Nothing was deleted. Drag Mectrics to the Trash instead, or run the uninstall script from the project page.")
        }
        .alert(
            Text("Mectrics could not relaunch."),
            isPresented: $relaunchFailed
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Quit and reopen Mectrics to apply the selected language.")
        }
    }

    private static var versionString: String {
        let bundle = Bundle.main
        let short = bundle.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "–"
        let build = bundle.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "–"
        return "\(short) (\(build))"
    }
}

/// A rule is either a percentage threshold on a module or a native system signal.
enum AlertRuleKey: Hashable, Identifiable {
    case metric(MetricID)
    case system(SystemAlertSignal)

    var id: String {
        switch self {
        case .metric(let id): return "metric.\(id.rawValue)"
        case .system(let signal): return "system.\(signal.rawValue)"
        }
    }
}

/// Alerts tab of the settings window.
///
/// Percentage thresholds and native system conditions are two implementations of the
/// same idea, so they share one list and one row anatomy. The primary line carries the
/// decision — what it watches, its limit, on or off — and the secondary line carries
/// live state plus the fine tuning.
///
/// As in `MenuBarBuilderView`, live readings are read only by leaf views
/// (`AlertRuleLiveLine`, `AlertRuleSummary`). This body must stay independent of
/// `AppModel.latest` so a new sample cannot rebuild the whole list of steppers,
/// pickers, and toggles once a second.
struct AlertsSettingsTab: View {
    @Bindable var model: AppModel
    @State private var notificationAccess = NotificationAccessState.unknown
    @State private var testResult: NotificationAccessState?
    @State private var cliInstallation = CLIInstaller.installationState()
    @State private var cliInstallationFailed = false

    private typealias RuleKey = AlertRuleKey

    var body: some View {
        Form {
            Section {
                notificationWarning
                ForEach(ruleKeys) { key in
                    ruleRow(key)
                }
            } header: {
                HStack {
                    Text("Rules")
                    Spacer()
                    AlertRuleSummary(model: model, keys: ruleKeys)
                }
            } footer: {
                Text("When a rule alerts it notifies you, marks the Compact Health item, and is recorded in the Attention Log. A rule rests for 15 minutes after it alerts.")
            }

            Section {
                if notificationAccess != .authorized {
                    LabeledContent(
                        "Permission",
                        value: notificationAccess.localizedName
                    )
                }
                HStack {
                    // macOS only offers its prompt while the choice is unmade; after
                    // that System Settings is the only route, so that button is always
                    // available rather than appearing once the user is already stuck.
                    if notificationAccess == .notDetermined {
                        Button("Allow Notifications…") {
                            requestNotificationAccess()
                        }
                    }
                    Button("Open Notification Settings") {
                        NotificationPermissionManager.openSystemSettings()
                    }
                    Button("Send a Test Notification") {
                        sendTestNotification()
                    }
                }
                if let testResult {
                    Text(testResult.testResultDescription)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Notifications")
            } footer: {
                Text("macOS owns notification permission and decides how alerts are presented. Mectrics cannot show one until you allow it there.")
            }

            Section {
                VStack(alignment: .leading, spacing: ExperienceSpacing.small) {
                    Text(
                        String(
                            localized: "alerts.cli.description",
                            defaultValue: "Install the bundled CLI to run mectrics from any Terminal. It remains read-only and uses the rules enabled above."
                        )
                    )
                    cliInstallationControl
                    if cliInstallationFailed {
                        Label(
                            String(
                                localized: "alerts.cli.failed",
                                defaultValue: "Installation was cancelled or failed. Nothing changed."
                            ),
                            systemImage: "xmark.circle"
                        )
                        .font(.caption)
                        .foregroundStyle(.red)
                    }
                    Text(
                        String(
                            localized: "alerts.cli.commands",
                            defaultValue: "Available commands"
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Text(
                        verbatim: """
                        mectrics check
                        mectrics check --json
                        mectrics snapshot --json
                        mectrics alerts watch --json
                        mectrics alerts watch --json --heartbeat 60
                        mectrics doctor --json
                        """
                    )
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                }
                .padding(.vertical, ExperienceSpacing.xSmall)
            } header: {
                Text(
                    String(
                        localized: "alerts.cli.title",
                        defaultValue: "Command Line Access"
                    )
                )
            } footer: {
                Text(
                    String(
                        localized: "alerts.cli.footer",
                        defaultValue: "Installation creates a link at /usr/local/bin/mectrics. macOS may ask for administrator permission."
                    )
                )
            }
        }
        .formStyle(.grouped)
        .onAppear {
            refreshNotificationAccess()
            cliInstallation = CLIInstaller.installationState()
        }
    }

    @ViewBuilder
    private var cliInstallationControl: some View {
        switch cliInstallation {
        case .installed:
            HStack {
                Label(
                    String(
                        localized: "alerts.cli.installed",
                        defaultValue: "Installed"
                    ),
                    systemImage: "checkmark.circle.fill"
                )
                .foregroundStyle(.green)
                Text(verbatim: "/usr/local/bin/mectrics")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                Spacer()
                Button(
                    String(
                        localized: "alerts.cli.remove",
                        defaultValue: "Remove"
                    )
                ) {
                    removeCLI()
                }
            }
        case .conflict:
            Label(
                String(
                    localized: "alerts.cli.conflict",
                    defaultValue: "A different command already exists at /usr/local/bin/mectrics."
                ),
                systemImage: "exclamationmark.triangle"
            )
            .foregroundStyle(.orange)
        case .notInstalled, .repairable:
            Button(
                String(
                    localized: "alerts.cli.install",
                    defaultValue: "Install CLI…"
                )
            ) {
                installCLI()
            }
        }
    }

    private func installCLI() {
        cliInstallationFailed = false
        switch CLIInstaller.install() {
        case .success:
            cliInstallation = CLIInstaller.installationState()
        case .conflict:
            cliInstallation = .conflict
        case .failed:
            cliInstallationFailed = true
        }
    }

    private func removeCLI() {
        cliInstallationFailed = false
        switch CLIInstaller.remove() {
        case .success:
            cliInstallation = CLIInstaller.installationState()
        case .conflict:
            cliInstallation = .conflict
        case .failed:
            cliInstallationFailed = true
        }
    }

    // MARK: - Rule list

    /// Module rules first, each followed by the native signals for the same hardware,
    /// so related rules read as one group.
    private var ruleKeys: [RuleKey] {
        var keys: [RuleKey] = []
        var placedSignals: Set<SystemAlertSignal> = []
        for id in model.alertableModules {
            keys.append(.metric(id))
            for signal in SystemAlertSignal.allCases
            where signal.metricID == id && isSignalAvailable(signal) {
                keys.append(.system(signal))
                placedSignals.insert(signal)
            }
        }
        for signal in SystemAlertSignal.allCases
        where !placedSignals.contains(signal) && isSignalAvailable(signal) {
            keys.append(.system(signal))
        }
        return keys
    }

    private func isSignalAvailable(_ signal: SystemAlertSignal) -> Bool {
        // The battery service signal only exists on Macs whose battery reports one.
        model.availableSystemAlertSignals.contains(signal)
    }

    /// A closed rule dims its limit control rather than moving or dropping it, so the
    /// switch and the limit stay in the same column on every row.
    @ViewBuilder
    private func ruleRow(_ key: RuleKey) -> some View {
        let enabled = isEnabled(key)
        VStack(alignment: .leading, spacing: ExperienceSpacing.small) {
            // Primary line: what it watches, its limit, and whether it is on.
            HStack(spacing: ExperienceSpacing.medium) {
                Text(label(for: key))
                Spacer(minLength: ExperienceSpacing.small)
                thresholdControl(key)
                    .disabled(!enabled)
                Toggle("", isOn: enabledBinding(key))
                    .labelsHidden()
                    .accessibilityLabel(label(for: key))
            }
            // Secondary line: how it is behaving right now and the fine tuning.
            if enabled {
                HStack(spacing: ExperienceSpacing.small) {
                    AlertRuleLiveLine(model: model, key: key)
                    Spacer()
                    durationPicker(key)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .controlSize(.small)
            }
        }
    }

    // MARK: - Row pieces

    /// Steppers and pickers draw at different intrinsic widths, so every limit control
    /// is trailing-aligned inside one shared column and the values line up down the
    /// list regardless of which control a rule uses.
    private func thresholdControl(_ key: RuleKey) -> some View {
        Group {
            switch key {
            case .metric(let id):
                let isTemp = id == .sensors
                let below = ThresholdMonitor.isBelowRule(id)
                let range = isTemp ? 60...105 : (below ? 5...50 : 50...100)
                HStack(spacing: ExperienceSpacing.xSmall) {
                    Text(thresholdSummary(key))
                        .monospacedDigit()
                    Stepper(
                        "",
                        value: metricRuleBinding(id).thresholdPercent,
                        in: range,
                        step: 5
                    )
                    .labelsHidden()
                }
            case .system(let signal):
                systemThresholdControl(signal)
            }
        }
        .frame(width: 136, alignment: .trailing)
        .accessibilityLabel("Limit")
    }

    @ViewBuilder
    private func systemThresholdControl(_ signal: SystemAlertSignal) -> some View {
        let rule = systemRuleBinding(signal)
        switch signal {
        case .thermalPressure:
            Picker("Slowdown", selection: rule.thresholdValue) {
                Text(ThermalPressureLevel.serious.localizedName)
                    .tag(Double(ThermalPressureLevel.serious.rawValue))
                Text(ThermalPressureLevel.critical.localizedName)
                    .tag(Double(ThermalPressureLevel.critical.rawValue))
            }
            .labelsHidden()
            .fixedSize()
        case .memoryPressure:
            Picker("Pressure level", selection: rule.thresholdValue) {
                Text(MemoryPressureLevel.warning.localizedName)
                    .tag(Double(MemoryPressureLevel.warning.rawValue))
                Text(MemoryPressureLevel.critical.localizedName)
                    .tag(Double(MemoryPressureLevel.critical.rawValue))
            }
            .labelsHidden()
            .fixedSize()
        case .diskAvailableCapacity:
            Picker("Available capacity", selection: rule.thresholdValue) {
                ForEach([5, 10, 20, 50], id: \.self) { gigabytes in
                    Text(
                        MetricFormat.bytes(
                            Double(gigabytes) * 1_024 * 1_024 * 1_024
                        )
                    )
                    .tag(Double(gigabytes) * 1_024 * 1_024 * 1_024)
                }
            }
            .labelsHidden()
            .fixedSize()
        case .batteryService:
            // macOS decides this one; there is nothing to configure.
            EmptyView()
        }
    }

    @ViewBuilder
    private func durationPicker(_ key: RuleKey) -> some View {
        Picker("Alert after", selection: durationBinding(key)) {
            Text("Alert right away").tag(0)
            Text("Alert after 30 seconds").tag(30)
            Text("Alert after 1 minute").tag(60)
            Text("Alert after 2 minutes").tag(120)
            Text("Alert after 5 minutes").tag(300)
        }
        .labelsHidden()
        .accessibilityLabel("Alert after")
        .fixedSize()
    }

    /// Rules that are on cannot notify until macOS allows it — a fact about the app,
    /// not about any one rule, so it is stated once above the list.
    @ViewBuilder
    private var notificationWarning: some View {
        if ruleKeys.contains(where: { isEnabled($0) }),
           notificationAccess == .denied
            || notificationAccess == .deliveryDisabled
            || notificationAccess == .notDetermined {
            HStack(spacing: ExperienceSpacing.small) {
                Label(
                    "macOS is not allowing notifications yet, so rules can only show on the Compact Health item.",
                    systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(.orange)
                Spacer()
                Button(notificationAccess == .notDetermined
                       ? "Allow…"
                       : "Open Settings…") {
                    if notificationAccess == .notDetermined {
                        requestNotificationAccess()
                    } else {
                        NotificationPermissionManager.openSystemSettings()
                    }
                }
                .buttonStyle(.link)
            }
            .font(.caption)
        }
    }

    // MARK: - Rule text

    private func label(for key: RuleKey) -> String {
        switch key {
        case .metric(let id):
            if id == .sensors {
                return String(
                    localized: "alerts.temp",
                    defaultValue: "CPU temperature above"
                )
            }
            return ThresholdMonitor.isBelowRule(id)
                ? String(
                    localized: "alerts.below",
                    defaultValue: "\(id.localizedName) charge below"
                )
                : String(
                    localized: "alerts.above",
                    defaultValue: "\(id.localizedName) usage above"
                )
        case .system(let signal):
            return signal.triggerLabel
        }
    }

    private func thresholdSummary(_ key: RuleKey) -> String {
        switch key {
        case .metric(let id):
            let rule = model.alertRules[id]
                ?? AlertRule(enabled: false, thresholdPercent: 90)
            return "\(rule.thresholdPercent)\(id == .sensors ? "°C" : "%")"
        case .system(let signal):
            let value = model.systemAlertRules[signal]?.thresholdValue ?? 0
            switch signal {
            case .thermalPressure:
                return SystemSignalFormat.thermal(value)
            case .memoryPressure:
                return SystemSignalFormat.pressure(value)
            case .diskAvailableCapacity:
                return MetricFormat.bytes(value)
            case .batteryService:
                return String(
                    localized: "alerts.threshold.macOS",
                    defaultValue: "macOS decides"
                )
            }
        }
    }

    // MARK: - Rule state

    private func isEnabled(_ key: RuleKey) -> Bool {
        switch key {
        case .metric(let id):
            return model.alertRules[id]?.enabled ?? false
        case .system(let signal):
            return model.systemAlertRules[signal]?.enabled ?? false
        }
    }

    // MARK: - Bindings

    private func metricRuleBinding(_ id: MetricID) -> Binding<AlertRule> {
        Binding(
            get: {
                model.alertRules[id]
                    ?? AlertRule(enabled: false, thresholdPercent: 90)
            },
            set: { newValue in
                let wasEnabled = model.alertRules[id]?.enabled ?? false
                model.alertRules[id] = newValue
                if !wasEnabled,
                   newValue.enabled,
                   newValue.destinations.contains(.notification) {
                    requestNotificationAccess()
                }
            }
        )
    }

    private func systemRuleBinding(
        _ signal: SystemAlertSignal
    ) -> Binding<SystemAlertRule> {
        Binding(
            get: {
                model.systemAlertRules[signal]
                    ?? SystemAlertRule(enabled: false, thresholdValue: 1)
            },
            set: { newValue in
                let wasEnabled =
                    model.systemAlertRules[signal]?.enabled ?? false
                model.systemAlertRules[signal] = newValue
                if !wasEnabled,
                   newValue.enabled,
                   newValue.destinations.contains(.notification) {
                    requestNotificationAccess()
                }
            }
        )
    }

    /// Turning a rule on also normalizes where it appears, so a layout saved by an
    /// older build cannot leave an enabled rule with nowhere to show up.
    private func enabledBinding(_ key: RuleKey) -> Binding<Bool> {
        Binding(
            get: { isEnabled(key) },
            set: { enabled in
                switch key {
                case .metric(let id):
                    guard var rule = model.alertRules[id] else { return }
                    rule.enabled = enabled
                    rule.destinations = Self.alertDestinations
                    model.alertRules[id] = rule
                case .system(let signal):
                    guard var rule = model.systemAlertRules[signal] else {
                        return
                    }
                    rule.enabled = enabled
                    rule.destinations = Self.alertDestinations
                    model.systemAlertRules[signal] = rule
                }
                if enabled { requestNotificationAccess() }
            }
        )
    }

    private func durationBinding(_ key: RuleKey) -> Binding<Int> {
        switch key {
        case .metric(let id):
            return metricRuleBinding(id).durationSeconds
        case .system(let signal):
            return systemRuleBinding(signal).durationSeconds
        }
    }

    /// Turning a rule on *is* the request to be told about it, so an alerting rule
    /// notifies, marks the Compact Health item, and is recorded — there is no second
    /// opt-in to forget.
    static let alertDestinations: Set<AlertDestination> = [
        .notification, .compactHealth, .attentionLog
    ]

    private func sendTestNotification() {
        NotificationPermissionManager.sendTest { state in
            Task { @MainActor in
                notificationAccess = state
                testResult = state
            }
        }
    }

    // MARK: - Notification access

    private func refreshNotificationAccess() {
        NotificationPermissionManager.current { state in
            Task { @MainActor in notificationAccess = state }
        }
    }

    private func requestNotificationAccess() {
        NotificationPermissionManager.request { state in
            Task { @MainActor in
                notificationAccess = state
                // macOS shows its prompt at most once per install. If the answer is
                // still unmade, no prompt appeared and System Settings is the only
                // way through — go there rather than leaving the button inert.
                if state == .notDetermined {
                    NotificationPermissionManager.openSystemSettings()
                }
            }
        }
    }
}

// MARK: - Leaves that read live values

/// How a rule is behaving right now. Kept in its own view so a new sample repaints
/// one caption instead of rebuilding every stepper, picker, and toggle in the list.
private struct AlertRuleLiveLine: View {
    let model: AppModel
    let key: AlertRuleKey

    var body: some View {
        let state = AlertRuleReading.state(model: model, key: key)
        Label(state.localizedName, systemImage: state.symbolName)
            .foregroundStyle(state.tint)
        Text("·")
        Text(AlertRuleReading.currentReading(model: model, key: key))
            .monospacedDigit()
    }
}

/// "3 on · 1 alerting" beside the section header.
private struct AlertRuleSummary: View {
    let model: AppModel
    let keys: [AlertRuleKey]

    var body: some View {
        Text(summary)
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
    }

    private var summary: String {
        let enabled = keys.filter { AlertRuleReading.isEnabled(model: model, key: $0) }
            .count
        guard enabled > 0 else {
            return String(
                localized: "alerts.summary.none",
                defaultValue: "No rules on"
            )
        }
        let alerting = keys.filter {
            AlertRuleReading.state(model: model, key: $0) == .active
        }.count
        return String(
            localized: "alerts.summary",
            defaultValue: "\(enabled) on · \(alerting) alerting"
        )
    }
}

/// Shared resolution of a rule's live state and reading.
@MainActor
private enum AlertRuleReading {
    static func isEnabled(model: AppModel, key: AlertRuleKey) -> Bool {
        switch key {
        case .metric(let id):
            return model.alertRules[id]?.enabled ?? false
        case .system(let signal):
            return model.systemAlertRules[signal]?.enabled ?? false
        }
    }

    static func state(model: AppModel, key: AlertRuleKey) -> AlertConditionState {
        switch key {
        case .metric(let id):
            guard let rule = model.alertRules[id],
                  rule.enabled,
                  let sample = model.latest[id]
            else { return .normal }
            let measured = sample.unit == .celsius
                ? sample.value
                : sample.value * 100
            let violating = ThresholdMonitor.isBelowRule(id)
                ? measured <= Double(rule.thresholdPercent)
                : measured >= Double(rule.thresholdPercent)
            guard violating else { return .normal }
            return model.alertConditionStates[id] == .active ? .active : .pending
        case .system(let signal):
            guard let rule = model.systemAlertRules[signal],
                  rule.enabled,
                  let reading = model.systemConditionReadings[signal],
                  SystemConditionMonitor.isViolating(
                      reading,
                      threshold: rule.thresholdValue
                  )
            else { return .normal }
            return model.systemConditionStates[signal] == .active
                ? .active
                : .pending
        }
    }

    static func currentReading(model: AppModel, key: AlertRuleKey) -> String {
        switch key {
        case .metric(let id):
            guard let sample = model.latest[id] else {
                return String(
                    localized: "state.unavailable",
                    defaultValue: "Unavailable"
                )
            }
            if sample.unit == .celsius {
                return String(format: "%.1f°C", sample.value)
            }
            return MetricFormat.percent(sample.value, decimals: 1)
        case .system(let signal):
            guard let reading = model.systemConditionReadings[signal] else {
                return String(
                    localized: "state.unavailable",
                    defaultValue: "Unavailable"
                )
            }
            switch signal {
            case .thermalPressure:
                return SystemSignalFormat.thermal(reading.value)
            case .memoryPressure:
                return SystemSignalFormat.pressure(reading.value)
            case .diskAvailableCapacity:
                return MetricFormat.bytes(reading.value)
            case .batteryService:
                return reading.value >= 1
                    ? String(
                        localized: "battery.service.recommended",
                        defaultValue: "Service recommended"
                    )
                    : String(
                        localized: "battery.service.normal",
                        defaultValue: "Normal"
                    )
            }
        }
    }
}

private extension AlertConditionState {
    var localizedName: String {
        switch self {
        case .normal:
            return String(localized: "alerts.state.normal", defaultValue: "Normal")
        case .pending:
            return String(localized: "alerts.state.pending", defaultValue: "Limit crossed, waiting")
        case .active:
            return String(localized: "alerts.state.active", defaultValue: "Alerting")
        }
    }

    var symbolName: String {
        switch self {
        case .normal: return "checkmark.circle"
        case .pending: return "clock"
        case .active: return "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .normal: return .secondary
        case .pending: return .orange
        case .active: return .red
        }
    }
}

private extension SystemAlertSignal {
    var triggerLabel: String {
        switch self {
        case .thermalPressure:
            return String(
                localized: "alerts.system.thermalPressure",
                defaultValue: "CPU and GPU slowed to cool down"
            )
        case .memoryPressure:
            return String(
                localized: "alerts.system.memoryPressure",
                defaultValue: "Memory pressure reaches"
            )
        case .diskAvailableCapacity:
            return String(
                localized: "alerts.system.diskCapacity",
                defaultValue: "Free disk space below"
            )
        case .batteryService:
            return String(
                localized: "alerts.system.batteryService",
                defaultValue: "macOS recommends battery service"
            )
        }
    }
}

private extension NotificationAccessState {
    var localizedName: String {
        switch self {
        case .unknown:
            return String(localized: "notifications.status.unknown", defaultValue: "Checking…")
        case .notDetermined:
            return String(localized: "notifications.status.notDetermined", defaultValue: "Not requested")
        case .authorized:
            return String(localized: "notifications.status.authorized", defaultValue: "Allowed")
        case .denied:
            return String(localized: "notifications.status.denied", defaultValue: "Denied")
        case .deliveryDisabled:
            return String(localized: "notifications.status.disabled", defaultValue: "Delivery disabled")
        }
    }

    var testResultDescription: String {
        switch self {
        case .authorized:
            return String(
                localized: "notifications.test.sent",
                defaultValue: "Test notification sent. It did not create an Attention Log event."
            )
        case .denied:
            return String(
                localized: "notifications.test.denied",
                defaultValue: "Notifications are denied. Open Notification Settings to allow them."
            )
        case .deliveryDisabled:
            return String(
                localized: "notifications.test.disabled",
                defaultValue: "Notification delivery is disabled in System Settings."
            )
        case .notDetermined:
            return String(
                localized: "notifications.test.notDetermined",
                defaultValue: "Notification permission has not been granted."
            )
        case .unknown:
            return String(
                localized: "notifications.test.failed",
                defaultValue: "The test notification could not be delivered."
            )
        }
    }
}
