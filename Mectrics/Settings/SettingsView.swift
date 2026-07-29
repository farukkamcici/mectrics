import SwiftUI
import MetricsKit

/// General preferences tab of the settings window. Tabs are hosted individually by
/// `SettingsWindowController`, which owns the per-tab window sizes.
struct GeneralSettingsTab: View {
    @Bindable var model: AppModel
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var summaryCopied = false

    var body: some View {
        Form {
            Section("Application") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        LoginItem.setEnabled(newValue)
                    }
                Button(role: .destructive) {
                    NSApp.terminate(nil)
                } label: {
                    Label("Quit Mectrics", systemImage: "power")
                }
            }

            Section("Floating panel") {
                Toggle("Show floating panel", isOn: $model.showFloatingPanel)
                Picker("Panel layout", selection: $model.panelLayout) {
                    ForEach(PanelLayout.allCases) { layout in
                        Text(layout.localizedName).tag(layout)
                    }
                }
                Text("Press Control–Option–M to show or hide the panel.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Energy Guard") {
                Toggle(
                    "Adapt monitoring to power and thermal state",
                    isOn: $model.adaptMonitoringToEnergyState
                )
                LabeledContent(
                    "Monitoring policy",
                    value: model.energyGuardMode.localizedName
                )
                Text("Mectrics keeps low-cost alerts responsive and reduces expensive sensor work first.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Data and privacy") {
                LabeledContent("Version", value: Self.versionString)
                Button("Open Attention Log") {
                    model.onOpenAttentionLog?()
                }
                Button("Copy System Summary") {
                    summaryCopied = SystemSummaryBuilder.copy(model: model)
                }
                Button("Open Diagnostics…") {
                    model.onOpenDiagnostics?()
                }
                if summaryCopied {
                    Text("System summary copied.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Button("Export metric history…") {
                    model.exportHistoryCSV()
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

    private static var versionString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
}

/// Alert thresholds tab of the settings window.
struct AlertsSettingsTab: View {
    @Bindable var model: AppModel
    @State private var notificationAccess = NotificationAccessState.unknown
    @State private var testResult: NotificationAccessState?

    var body: some View {
        Form {
            Section("Rules") {
                ForEach(model.alertableModules, id: \.self) { id in
                    alertRow(id)
                }
            }
            Section("System conditions") {
                systemAlertRow(.memoryPressure)
                systemAlertRow(.diskAvailableCapacity)
                systemAlertRow(.thermalState)
                if model.systemConditionReadings[.batteryService] != nil {
                    systemAlertRow(.batteryService)
                }
            }
            Section("Notification delivery") {
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
                Text("macOS controls the final presentation and delivery of notifications.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section {
                Text("A rule becomes pending when its reading crosses the limit, activates after the selected duration, and recovers when the reading returns to normal. Each rule has a 15-minute cooldown.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { refreshNotificationAccess() }
    }

    @ViewBuilder
    private func systemAlertRow(_ signal: SystemAlertSignal) -> some View {
        let rule = systemRuleBinding(signal)
        VStack(alignment: .leading, spacing: ExperienceSpacing.small) {
            HStack {
                Toggle(signal.triggerLabel, isOn: rule.enabled)
                Spacer()
                systemThresholdControl(signal, rule: rule)
                Picker(
                    "Sustained duration",
                    selection: rule.durationSeconds
                ) {
                    Text("Immediately").tag(0)
                    Text("30 seconds").tag(30)
                    Text("1 minute").tag(60)
                    Text("2 minutes").tag(120)
                    Text("5 minutes").tag(300)
                }
                .labelsHidden()
                .accessibilityLabel("Sustained duration")
                .frame(width: 120)
                .disabled(!rule.wrappedValue.enabled)
            }
            if rule.wrappedValue.enabled {
                HStack {
                    let state = systemPreviewState(
                        signal,
                        rule: rule.wrappedValue
                    )
                    Label(state.localizedName, systemImage: state.symbolName)
                    Spacer()
                    Text(systemCurrentReading(signal))
                        .monospacedDigit()
                    Text("·")
                    Text(durationSummary(rule.wrappedValue.durationSeconds))
                    Text("·")
                    Text("15 min cooldown")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                DisclosureGroup("Destinations") {
                    Toggle(
                        "Notification",
                        isOn: systemDestinationBinding(
                            .notification,
                            for: signal
                        )
                    )
                    Toggle(
                        "Compact Health item",
                        isOn: systemDestinationBinding(
                            .compactHealth,
                            for: signal
                        )
                    )
                    Toggle(
                        "Attention Log",
                        isOn: systemDestinationBinding(
                            .attentionLog,
                            for: signal
                        )
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func systemThresholdControl(
        _ signal: SystemAlertSignal,
        rule: Binding<SystemAlertRule>
    ) -> some View {
        switch signal {
        case .memoryPressure:
            Picker("Pressure level", selection: rule.thresholdValue) {
                Text("Warning").tag(2.0)
                Text("Critical").tag(4.0)
            }
            .labelsHidden()
            .frame(width: 90)
            .disabled(!rule.wrappedValue.enabled)
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
            .frame(width: 90)
            .disabled(!rule.wrappedValue.enabled)
        case .thermalState:
            Picker("Thermal state", selection: rule.thresholdValue) {
                Text("Serious").tag(2.0)
                Text("Critical").tag(3.0)
            }
            .labelsHidden()
            .frame(width: 90)
            .disabled(!rule.wrappedValue.enabled)
        case .batteryService:
            Text("macOS status")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func alertRow(_ id: MetricID) -> some View {
        let rule = ruleBinding(id)
        let below = ThresholdMonitor.isBelowRule(id)
        let isTemp = id == .sensors
        let range = isTemp ? 60...105 : (below ? 5...50 : 50...100)
        let label = isTemp
            ? String(localized: "alerts.temp", defaultValue: "CPU temperature above")
            : (below
               ? String(localized: "alerts.below", defaultValue: "\(id.localizedName) below")
               : String(localized: "alerts.above", defaultValue: "\(id.localizedName) above"))
        VStack(alignment: .leading, spacing: ExperienceSpacing.small) {
            HStack {
                Toggle(isOn: rule.enabled) {
                    Text(label)
                }
                Spacer()
                Stepper(value: rule.thresholdPercent, in: range, step: 5) {
                    Text("\(rule.wrappedValue.thresholdPercent)\(isTemp ? "°C" : "%")")
                        .monospacedDigit()
                        .frame(minWidth: 40, alignment: .trailing)
                }
                .disabled(!rule.wrappedValue.enabled)
                Picker("Sustained duration", selection: rule.durationSeconds) {
                    Text("Immediately").tag(0)
                    Text("30 seconds").tag(30)
                    Text("1 minute").tag(60)
                    Text("2 minutes").tag(120)
                    Text("5 minutes").tag(300)
                }
                .labelsHidden()
                .accessibilityLabel("Sustained duration")
                .frame(width: 120)
                .disabled(!rule.wrappedValue.enabled)
            }
            if rule.wrappedValue.enabled {
                HStack {
                    Label(
                        previewState(for: id, rule: rule.wrappedValue).localizedName,
                        systemImage: previewState(
                            for: id,
                            rule: rule.wrappedValue
                        ).symbolName
                    )
                    Spacer()
                    Text(currentReading(for: id))
                        .monospacedDigit()
                    Text("·")
                    Text(durationSummary(rule.wrappedValue.durationSeconds))
                    Text("·")
                    Text("15 min cooldown")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                DisclosureGroup("Destinations") {
                    Toggle(
                        "Notification",
                        isOn: destinationBinding(.notification, for: id)
                    )
                    Toggle(
                        "Compact Health item",
                        isOn: destinationBinding(.compactHealth, for: id)
                    )
                    Toggle(
                        "Attention Log",
                        isOn: destinationBinding(.attentionLog, for: id)
                    )
                }
            }
        }
    }

    private func ruleBinding(_ id: MetricID) -> Binding<AlertRule> {
        Binding(
            get: { model.alertRules[id] ?? AlertRule(enabled: false, thresholdPercent: 90) },
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

    private func destinationBinding(
        _ destination: AlertDestination,
        for id: MetricID
    ) -> Binding<Bool> {
        Binding(
            get: { model.alertRules[id]?.destinations.contains(destination) ?? false },
            set: { enabled in
                guard var rule = model.alertRules[id] else { return }
                if enabled {
                    rule.destinations.insert(destination)
                } else {
                    rule.destinations.remove(destination)
                }
                model.alertRules[id] = rule
                if enabled, destination == .notification {
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

    private func systemDestinationBinding(
        _ destination: AlertDestination,
        for signal: SystemAlertSignal
    ) -> Binding<Bool> {
        Binding(
            get: {
                model.systemAlertRules[signal]?
                    .destinations.contains(destination) ?? false
            },
            set: { enabled in
                guard var rule = model.systemAlertRules[signal] else { return }
                if enabled {
                    rule.destinations.insert(destination)
                } else {
                    rule.destinations.remove(destination)
                }
                model.systemAlertRules[signal] = rule
                if enabled, destination == .notification {
                    requestNotificationAccess()
                }
            }
        )
    }

    private func previewState(
        for id: MetricID,
        rule: AlertRule
    ) -> AlertConditionState {
        guard rule.enabled, let sample = model.latest[id] else { return .normal }
        let measured = sample.unit == .celsius ? sample.value : sample.value * 100
        let violating = ThresholdMonitor.isBelowRule(id)
            ? measured <= Double(rule.thresholdPercent)
            : measured >= Double(rule.thresholdPercent)
        guard violating else { return .normal }
        return model.alertConditionStates[id] == .active ? .active : .pending
    }

    private func systemPreviewState(
        _ signal: SystemAlertSignal,
        rule: SystemAlertRule
    ) -> AlertConditionState {
        guard rule.enabled,
              let reading = model.systemConditionReadings[signal]
        else {
            return .normal
        }
        guard SystemConditionMonitor.isViolating(
            reading,
            threshold: rule.thresholdValue
        ) else {
            return .normal
        }
        return model.systemConditionStates[signal] == .active
            ? .active
            : .pending
    }

    private func systemCurrentReading(_ signal: SystemAlertSignal) -> String {
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

    private func currentReading(for id: MetricID) -> String {
        guard let sample = model.latest[id] else {
            return String(localized: "state.unavailable", defaultValue: "Unavailable")
        }
        if sample.unit == .celsius {
            return String(format: "%.1f°C", sample.value)
        }
        return MetricFormat.percent(sample.value, decimals: 1)
    }

    private func durationSummary(_ seconds: Int) -> String {
        switch seconds {
        case 0:
            return String(localized: "alerts.duration.immediately", defaultValue: "Immediately")
        case 30:
            return String(localized: "alerts.duration.30seconds", defaultValue: "30 sec")
        case 60:
            return String(localized: "alerts.duration.1minute", defaultValue: "1 min")
        case 120:
            return String(localized: "alerts.duration.2minutes", defaultValue: "2 min")
        case 300:
            return String(localized: "alerts.duration.5minutes", defaultValue: "5 min")
        default:
            return "\(seconds)s"
        }
    }

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
