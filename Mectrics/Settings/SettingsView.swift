import SwiftUI
import MetricsKit

/// Settings window — module selection and general preferences.
struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
            modulesTab
                .tabItem { Label("Modules", systemImage: "square.grid.2x2") }
        }
        .frame(width: 420, height: 300)
    }

    private var generalTab: some View {
        Form {
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    LoginItem.setEnabled(newValue)
                }
            LabeledContent("Version", value: "0.1.0 (MVP)")
            LabeledContent("Privacy", value: String(localized: "settings.privacy.value",
                defaultValue: "Zero telemetry — no data ever leaves your device"))
        }
        .formStyle(.grouped)
        .padding()
    }

    private var modulesTab: some View {
        Form {
            Section("Show in menu bar") {
                ForEach(model.availableModules, id: \.self) { id in
                    Toggle(id.localizedName, isOn: Binding(
                        get: { model.enabledModules.contains(id) },
                        set: { model.setEnabled($0, for: id) }
                    ))
                }
            }
            if model.availableModules.count < MetricID.allCases.count {
                Section {
                    Text("GPU, Sensors and Fan modules will be added in future releases.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
