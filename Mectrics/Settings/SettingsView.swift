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

            Section("Charts") {
                Picker("Battery and disk history", selection: $model.detailHistoryRange) {
                    ForEach(DetailHistoryRange.allCases) { range in
                        Text(range.localizedName).tag(range)
                    }
                }
            }

            Section("Data and privacy") {
                LabeledContent("Version", value: Self.versionString)
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

enum DetailHistoryRange: Int, CaseIterable, Identifiable {
    case day = 24
    case week = 168
    case month = 720

    var id: Int { rawValue }
    var duration: TimeInterval { TimeInterval(rawValue * 60 * 60) }

    var localizedName: String {
        switch self {
        case .day:
            return String(localized: "history.range.day", defaultValue: "24 hours")
        case .week:
            return String(localized: "history.range.week", defaultValue: "7 days")
        case .month:
            return String(localized: "history.range.month", defaultValue: "30 days")
        }
    }
}

/// Alert thresholds tab of the settings window.
struct AlertsSettingsTab: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section("Notify me when") {
                ForEach(model.alertableModules, id: \.self) { id in
                    alertRow(id)
                }
            }
            Section {
                Text("An alert appears after the reading stays beyond its limit for the selected time. Each module alerts at most once every 15 minutes.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

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
        return HStack {
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
            Picker("For", selection: rule.durationSeconds) {
                Text("Immediately").tag(0)
                Text("30 seconds").tag(30)
                Text("1 minute").tag(60)
                Text("2 minutes").tag(120)
                Text("5 minutes").tag(300)
            }
            .labelsHidden()
            .frame(width: 120)
            .disabled(!rule.wrappedValue.enabled)
        }
    }

    private func ruleBinding(_ id: MetricID) -> Binding<AlertRule> {
        Binding(
            get: { model.alertRules[id] ?? AlertRule(enabled: false, thresholdPercent: 90) },
            set: { newValue in
                if newValue.enabled { ThresholdMonitor.requestAuthorizationIfNeeded() }
                model.alertRules[id] = newValue
            }
        )
    }
}
