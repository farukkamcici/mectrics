import SwiftUI

/// Mectrics — menü çubuğu sistem monitörü.
///
/// Uygulama bir "accessory" (menü çubuğu ajanı) olarak çalışır: Dock ikonu ve ana pencere
/// yoktur. Menü çubuğu öğeleri `AppDelegate` içindeki `MenuBarController` tarafından
/// yönetilir. Buradaki `Settings` sahnesi yalnızca ayarlar penceresini sağlar.
@main
struct MectricsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(model: appDelegate.model)
        }
    }
}
