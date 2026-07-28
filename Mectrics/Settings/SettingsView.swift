import SwiftUI
import MetricsKit

/// Ayarlar penceresi — modül seçimi ve genel tercihler.
struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("Genel", systemImage: "gearshape") }
            modulesTab
                .tabItem { Label("Modüller", systemImage: "square.grid.2x2") }
        }
        .frame(width: 420, height: 300)
    }

    private var generalTab: some View {
        Form {
            Toggle("Girişte başlat", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    LoginItem.setEnabled(newValue)
                }
            LabeledContent("Sürüm", value: "0.1.0 (MVP)")
            LabeledContent("Gizlilik", value: "Sıfır telemetri — hiçbir veri cihazdan çıkmaz")
        }
        .formStyle(.grouped)
        .padding()
    }

    private var modulesTab: some View {
        Form {
            Section("Menü çubuğunda göster") {
                ForEach(model.availableModules, id: \.self) { id in
                    Toggle(id.displayName, isOn: Binding(
                        get: { model.enabledModules.contains(id) },
                        set: { model.setEnabled($0, for: id) }
                    ))
                }
            }
            if model.availableModules.count < MetricID.allCases.count {
                Section {
                    Text("Ağ, Disk, GPU, Sensör ve Fan modülleri sonraki sürümlerde eklenecek.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
