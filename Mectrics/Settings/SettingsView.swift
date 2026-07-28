import SwiftUI
import MetricsKit

/// Settings window — module selection and general preferences. The window sizes itself
/// to the content (`.windowResizability(.contentSize)` on the scene), so each tab sets
/// its own natural height.
struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
            modulesTab
                .tabItem { Label("Modules", systemImage: "square.grid.2x2") }
            alertsTab
                .tabItem { Label("Alerts", systemImage: "bell.badge") }
        }
        .frame(width: 440)
        // The toggle can be flipped elsewhere (onboarding); re-read on every appearance.
        .onAppear { launchAtLogin = LoginItem.isEnabled }
    }

    private var generalTab: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        LoginItem.setEnabled(newValue)
                    }
                Toggle("Show floating panel", isOn: $model.showFloatingPanel)
                Picker("Panel layout", selection: $model.panelLayout) {
                    ForEach(PanelLayout.allCases) { layout in
                        Text(layout.localizedName).tag(layout)
                    }
                }
                LabeledContent("Panel hotkey", value: "⌃⌥M")
            }
            Section("Appearance") {
                Toggle(isOn: $model.showMenuBarIcons) {
                    Text("Icons in menu bar items")
                    Text("A small hardware icon at the start of each item.")
                }
                Picker("Accent color", selection: $model.accentChoice) {
                    ForEach(AccentChoice.allCases) { choice in
                        Text(choice.localizedName).tag(choice)
                    }
                }
            }
            Section {
                LabeledContent("Version", value: Self.versionString)
                Label("Zero telemetry — no data ever leaves your device",
                      systemImage: "lock.shield")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(height: 310)
    }

    private var modulesTab: some View {
        MenuBarBuilderView(model: model)
            .frame(height: 460)
    }

    private var alertsTab: some View {
        Form {
            Section("Notify me when") {
                ForEach(model.alertableModules, id: \.self) { id in
                    alertRow(id)
                }
            }
            Section {
                Text("Alerts fire when a value crosses its threshold, at most once every 15 minutes per module.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(height: 300)
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

    private static var versionString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
}
