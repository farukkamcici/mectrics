import SwiftUI
import MetricsKit

/// General preferences tab of the settings window. Tabs are hosted individually by
/// `SettingsWindowController`, which owns the per-tab window sizes.
struct GeneralSettingsTab: View {
    @Bindable var model: AppModel
    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        Form {
            Section("Application") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        LoginItem.setEnabled(newValue)
                    }
            }

            Section("Monitoring") {
                Toggle(
                    "Adapt monitoring to power and thermal state",
                    isOn: $model.adaptMonitoringToEnergyState
                )
                if model.adaptMonitoringToEnergyState {
                    LabeledContent("Currently") {
                        Text(
                            String(
                                localized: "energyGuard.currently",
                                defaultValue: "\(model.energyGuardMode.localizedName) — \(model.energyGuardReason.localizedName)"
                            )
                        )
                        .foregroundStyle(.secondary)
                    }
                }
                Text("Alerts stay responsive; expensive sensor readings slow down first.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Activity") {
                Button("Open Attention Log") {
                    model.onOpenAttentionLog?()
                }
                Button("Open Diagnostics…") {
                    model.onOpenDiagnostics?()
                }
                Label("Your readings stay on this Mac. Mectrics has no telemetry.",
                      systemImage: "lock.shield")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        // The toggle can be flipped elsewhere (onboarding); re-read on every appearance.
        .onAppear { launchAtLogin = LoginItem.isEnabled }
    }
}

/// Alerts tab of the settings window.
///
/// Percentage thresholds and native system conditions are two implementations of the
/// same idea, so they share one list and one row anatomy: what it watches, whether it
/// is on, its limit, how long it must hold, and where it shows up.
struct AlertsSettingsTab: View {
    @Bindable var model: AppModel
    @State private var notificationAccess = NotificationAccessState.unknown
    @State private var testResult: NotificationAccessState?

    /// A rule is either a percentage threshold on a module or a native system signal.
    private enum RuleKey: Hashable, Identifiable {
        case metric(MetricID)
        case system(SystemAlertSignal)

        var id: String {
            switch self {
            case .metric(let id): return "metric.\(id.rawValue)"
            case .system(let signal): return "system.\(signal.rawValue)"
            }
        }
    }

    var body: some View {
        Form {
            Section {
                ForEach(ruleKeys) { key in
                    ruleRow(key)
                }
            } header: {
                HStack {
                    Text("Rules")
                    Spacer()
                    Text(ruleSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            } footer: {
                Text("A rule becomes pending when its reading crosses the limit, activates once the reading holds for the chosen duration, and recovers on its own. Each rule waits 15 minutes before it can activate again.")
            }

            Section("Notifications") {
                LabeledContent(
                    "Permission",
                    value: notificationAccess.localizedName
                )
                HStack {
                    Button("Test Notification") {
                        NotificationPermissionManager.sendTest { state in
                            Task { @MainActor in
                                notificationAccess = state
                                testResult = state
                            }
                        }
                    }
                    if notificationAccess == .denied
                        || notificationAccess == .deliveryDisabled {
                        Button("Open Notification Settings") {
                            NotificationPermissionManager.openSystemSettings()
                        }
                    }
                }
                if let testResult {
                    Text(testResult.testResultDescription)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { refreshNotificationAccess() }
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
        signal != .batteryService
            || model.systemConditionReadings[.batteryService] != nil
    }

    private var ruleSummary: String {
        let enabled = ruleKeys.filter { isEnabled($0) }.count
        guard enabled > 0 else {
            return String(
                localized: "alerts.summary.none",
                defaultValue: "No rules on"
            )
        }
        let active = ruleKeys.filter { state(for: $0) == .active }.count
        return String(
            localized: "alerts.summary",
            defaultValue: "\(enabled) on · \(active) active now"
        )
    }

    @ViewBuilder
    private func ruleRow(_ key: RuleKey) -> some View {
        let enabled = isEnabled(key)
        VStack(alignment: .leading, spacing: ExperienceSpacing.small) {
            HStack {
                Toggle(label(for: key), isOn: enabledBinding(key))
                Spacer()
                if enabled {
                    thresholdControl(key)
                    durationPicker(key)
                } else {
                    // Closed rules keep their limit legible without offering dead
                    // controls.
                    Text(thresholdSummary(key))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            if enabled {
                let ruleState = state(for: key)
                HStack(spacing: ExperienceSpacing.xSmall) {
                    Label(
                        ruleState.localizedName,
                        systemImage: ruleState.symbolName
                    )
                    .foregroundStyle(ruleState.tint)
                    Text("·")
                    Text(currentReading(key))
                        .monospacedDigit()
                    Spacer()
                    destinationsMenu(key)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                notificationWarning(key)
            }
        }
    }

    // MARK: - Row pieces

    @ViewBuilder
    private func thresholdControl(_ key: RuleKey) -> some View {
        switch key {
        case .metric(let id):
            let isTemp = id == .sensors
            let below = ThresholdMonitor.isBelowRule(id)
            let range = isTemp ? 60...105 : (below ? 5...50 : 50...100)
            Stepper(
                value: metricRuleBinding(id).thresholdPercent,
                in: range,
                step: 5
            ) {
                Text(thresholdSummary(key))
                    .monospacedDigit()
                    .frame(minWidth: 44, alignment: .trailing)
            }
        case .system(let signal):
            systemThresholdControl(signal)
        }
    }

    @ViewBuilder
    private func systemThresholdControl(_ signal: SystemAlertSignal) -> some View {
        let rule = systemRuleBinding(signal)
        switch signal {
        case .memoryPressure:
            Picker("Pressure level", selection: rule.thresholdValue) {
                Text("Warning").tag(2.0)
                Text("Critical").tag(4.0)
            }
            .labelsHidden()
            .frame(width: 96)
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
            .frame(width: 96)
        case .thermalState:
            Picker("Thermal state", selection: rule.thresholdValue) {
                Text("Serious").tag(2.0)
                Text("Critical").tag(3.0)
            }
            .labelsHidden()
            .frame(width: 96)
        case .batteryService:
            // macOS decides this one; there is nothing to configure.
            EmptyView()
        }
    }

    @ViewBuilder
    private func durationPicker(_ key: RuleKey) -> some View {
        Picker("Sustained duration", selection: durationBinding(key)) {
            Text("Immediately").tag(0)
            Text("30 seconds").tag(30)
            Text("1 minute").tag(60)
            Text("2 minutes").tag(120)
            Text("5 minutes").tag(300)
        }
        .labelsHidden()
        .accessibilityLabel("Sustained duration")
        .frame(width: 124)
    }

    private func destinationsMenu(_ key: RuleKey) -> some View {
        Menu {
            Toggle(
                "Notification",
                isOn: destinationBinding(.notification, for: key)
            )
            Toggle(
                "Compact Health item",
                isOn: destinationBinding(.compactHealth, for: key)
            )
            Toggle(
                "Attention Log",
                isOn: destinationBinding(.attentionLog, for: key)
            )
        } label: {
            Text(destinationSummary(key))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("Where this alert appears")
    }

    private func destinationSummary(_ key: RuleKey) -> String {
        let destinations = destinations(for: key)
        guard !destinations.isEmpty else {
            return String(
                localized: "alerts.destination.none",
                defaultValue: "Goes nowhere"
            )
        }
        let names = AlertDestination.allCases
            .filter { destinations.contains($0) }
            .map(\.localizedName)
        guard let first = names.first else { return "" }
        if names.count == 1 { return first }
        return String(
            localized: "alerts.destination.summary",
            defaultValue: "\(first) +\(names.count - 1)"
        )
    }

    /// A rule that only delivers notifications is silent until macOS allows them.
    @ViewBuilder
    private func notificationWarning(_ key: RuleKey) -> some View {
        if destinations(for: key).contains(.notification),
           notificationAccess == .denied
            || notificationAccess == .deliveryDisabled
            || notificationAccess == .notDetermined {
            HStack(spacing: ExperienceSpacing.xSmall) {
                Label(
                    "Notifications are not allowed yet, so this rule will stay silent.",
                    systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(.orange)
                Button("Allow…") {
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
                    defaultValue: "\(id.localizedName) below"
                )
                : String(
                    localized: "alerts.above",
                    defaultValue: "\(id.localizedName) above"
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
            case .memoryPressure:
                return SystemSignalFormat.pressure(value)
            case .diskAvailableCapacity:
                return MetricFormat.bytes(value)
            case .thermalState:
                return SystemSignalFormat.thermal(value)
            case .batteryService:
                return String(
                    localized: "alerts.threshold.macOS",
                    defaultValue: "macOS decides"
                )
            }
        }
    }

    private func currentReading(_ key: RuleKey) -> String {
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
            case .memoryPressure:
                return SystemSignalFormat.pressure(reading.value)
            case .diskAvailableCapacity:
                return MetricFormat.bytes(reading.value)
            case .thermalState:
                return SystemSignalFormat.thermal(reading.value)
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

    // MARK: - Rule state

    private func isEnabled(_ key: RuleKey) -> Bool {
        switch key {
        case .metric(let id):
            return model.alertRules[id]?.enabled ?? false
        case .system(let signal):
            return model.systemAlertRules[signal]?.enabled ?? false
        }
    }

    private func destinations(for key: RuleKey) -> Set<AlertDestination> {
        switch key {
        case .metric(let id):
            return model.alertRules[id]?.destinations ?? []
        case .system(let signal):
            return model.systemAlertRules[signal]?.destinations ?? []
        }
    }

    private func state(for key: RuleKey) -> AlertConditionState {
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

    private func enabledBinding(_ key: RuleKey) -> Binding<Bool> {
        switch key {
        case .metric(let id):
            return metricRuleBinding(id).enabled
        case .system(let signal):
            return systemRuleBinding(signal).enabled
        }
    }

    private func durationBinding(_ key: RuleKey) -> Binding<Int> {
        switch key {
        case .metric(let id):
            return metricRuleBinding(id).durationSeconds
        case .system(let signal):
            return systemRuleBinding(signal).durationSeconds
        }
    }

    private func destinationBinding(
        _ destination: AlertDestination,
        for key: RuleKey
    ) -> Binding<Bool> {
        Binding(
            get: { destinations(for: key).contains(destination) },
            set: { enabled in
                switch key {
                case .metric(let id):
                    guard var rule = model.alertRules[id] else { return }
                    if enabled {
                        rule.destinations.insert(destination)
                    } else {
                        rule.destinations.remove(destination)
                    }
                    model.alertRules[id] = rule
                case .system(let signal):
                    guard var rule = model.systemAlertRules[signal] else {
                        return
                    }
                    if enabled {
                        rule.destinations.insert(destination)
                    } else {
                        rule.destinations.remove(destination)
                    }
                    model.systemAlertRules[signal] = rule
                }
                if enabled, destination == .notification {
                    requestNotificationAccess()
                }
            }
        )
    }

    // MARK: - Notification access

    private func refreshNotificationAccess() {
        NotificationPermissionManager.current { state in
            Task { @MainActor in notificationAccess = state }
        }
    }

    private func requestNotificationAccess() {
        NotificationPermissionManager.request { state in
            Task { @MainActor in notificationAccess = state }
        }
    }
}

private extension AlertDestination {
    var localizedName: String {
        switch self {
        case .notification:
            return String(
                localized: "alerts.destination.notification",
                defaultValue: "Notification"
            )
        case .compactHealth:
            return String(
                localized: "alerts.destination.compactHealth",
                defaultValue: "Compact Health item"
            )
        case .attentionLog:
            return String(
                localized: "alerts.destination.attentionLog",
                defaultValue: "Attention Log"
            )
        }
    }
}

private extension AlertConditionState {
    var localizedName: String {
        switch self {
        case .normal:
            return String(localized: "alerts.state.normal", defaultValue: "Normal")
        case .pending:
            return String(localized: "alerts.state.pending", defaultValue: "Pending")
        case .active:
            return String(localized: "alerts.state.active", defaultValue: "Active")
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
        case .memoryPressure:
            return String(
                localized: "alerts.system.memoryPressure",
                defaultValue: "Memory pressure reaches"
            )
        case .diskAvailableCapacity:
            return String(
                localized: "alerts.system.diskCapacity",
                defaultValue: "Available disk space below"
            )
        case .thermalState:
            return String(
                localized: "alerts.system.thermalState",
                defaultValue: "Thermal state reaches"
            )
        case .batteryService:
            return String(
                localized: "alerts.system.batteryService",
                defaultValue: "Battery service recommended by macOS"
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
