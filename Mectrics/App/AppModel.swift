import Foundation
import Observation
import MetricsKit

/// UI ile MetricsKit motoru arasındaki köprü. `@Observable` → SwiftUI görünümleri
/// `latest` değiştikçe otomatik güncellenir.
@Observable
final class AppModel {
    let engine: MetricsEngine

    /// Bu makinede kullanılabilir çekirdek modüller (ör. masaüstünde pil yok).
    let availableModules: [MetricID]

    /// Her modülün son örneği (menü çubuğu + popover bunu okur).
    var latest: [MetricID: MetricSample] = [:]

    /// Kullanıcının menü çubuğunda göstermeyi seçtiği modüller.
    var enabledModules: Set<MetricID> {
        didSet {
            persistEnabled()
            if enabledModules != oldValue { onModulesChanged?() }
        }
    }

    /// Etkin modül kümesi değişince menü çubuğunu yeniden kurmak için (AppDelegate bağlar).
    @ObservationIgnored var onModulesChanged: (() -> Void)?

    /// Accent rengi tercihi (basitlik için sistem accent'i varsayılan).
    var useSystemAccent = true

    private let defaults = UserDefaults.standard
    private static let enabledKey = "enabledModules"

    init() {
        let providers = MetricsKit.coreProviders()
        let available = providers.filter { $0.isAvailable }.map { $0.id }
        self.availableModules = available

        let engine = MetricsEngine()
        engine.register(providers)
        self.engine = engine

        // Kayıtlı seçim yoksa tüm mevcut modülleri aç.
        if let raw = defaults.array(forKey: Self.enabledKey) as? [String] {
            let restored = raw.compactMap { MetricID(rawValue: $0) }.filter { available.contains($0) }
            self.enabledModules = restored.isEmpty ? Set(available) : Set(restored)
        } else {
            self.enabledModules = Set(available)
        }
    }

    /// Modülleri menü çubuğu sırasına göre (CPU, Bellek, Pil ...) verir.
    var orderedEnabledModules: [MetricID] {
        availableModules.filter { enabledModules.contains($0) }
    }

    func setEnabled(_ enabled: Bool, for id: MetricID) {
        if enabled { enabledModules.insert(id) } else { enabledModules.remove(id) }
    }

    /// Sparkline için normalize edilmiş geçmiş.
    func history(_ id: MetricID, count: Int = 40) -> [Double] {
        engine.store.history(id, count: count).map(\.normalized)
    }

    private func persistEnabled() {
        defaults.set(enabledModules.map(\.rawValue), forKey: Self.enabledKey)
    }
}
