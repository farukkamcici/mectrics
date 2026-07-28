import Foundation
import Observation
import MetricsKit

/// Bridge between the UI and the MetricsKit engine. `@Observable` → SwiftUI views update
/// automatically as `latest` changes.
@Observable
final class AppModel {
    let engine: MetricsEngine

    /// Core modules available on this machine (e.g. no battery on a desktop).
    let availableModules: [MetricID]

    /// The latest sample per module (read by the menu bar + popover).
    var latest: [MetricID: MetricSample] = [:]

    /// Modules the user chose to show in the menu bar.
    var enabledModules: Set<MetricID> {
        didSet {
            persistEnabled()
            if enabledModules != oldValue { onModulesChanged?() }
        }
    }

    /// Called when the enabled-module set changes, so the menu bar can be rebuilt
    /// (wired by AppDelegate).
    @ObservationIgnored var onModulesChanged: (() -> Void)?

    /// Accent color preference (system accent by default for simplicity).
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

        // If nothing was persisted, enable all available modules.
        if let raw = defaults.array(forKey: Self.enabledKey) as? [String] {
            let restored = raw.compactMap { MetricID(rawValue: $0) }.filter { available.contains($0) }
            self.enabledModules = restored.isEmpty ? Set(available) : Set(restored)
        } else {
            self.enabledModules = Set(available)
        }
    }

    /// Modules in menu bar order (CPU, Memory, Battery ...).
    var orderedEnabledModules: [MetricID] {
        availableModules.filter { enabledModules.contains($0) }
    }

    func setEnabled(_ enabled: Bool, for id: MetricID) {
        if enabled { enabledModules.insert(id) } else { enabledModules.remove(id) }
    }

    /// Normalized history for sparklines.
    func history(_ id: MetricID, count: Int = 40) -> [Double] {
        engine.store.history(id, count: count).map(\.normalized)
    }

    private func persistEnabled() {
        defaults.set(enabledModules.map(\.rawValue), forKey: Self.enabledKey)
    }
}
