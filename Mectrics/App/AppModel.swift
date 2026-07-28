import AppKit
import Foundation
import Observation
import SwiftUI
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

    /// Whether the floating panel (always-on-top live widget) is visible.
    var showFloatingPanel: Bool {
        didSet {
            defaults.set(showFloatingPanel, forKey: Self.floatingPanelKey)
            if showFloatingPanel != oldValue { onFloatingPanelChanged?(showFloatingPanel) }
        }
    }

    /// Called when the floating panel visibility changes (wired by AppDelegate).
    @ObservationIgnored var onFloatingPanelChanged: ((Bool) -> Void)?

    /// One-shot flag: the first-launch onboarding has been shown and dismissed.
    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Self.onboardingKey) }
    }

    /// Accent color for sparklines/charts (`.system` follows macOS accent).
    var accentChoice: AccentChoice {
        didSet {
            defaults.set(accentChoice.rawValue, forKey: Self.accentKey)
            if accentChoice != oldValue { onAppearanceChanged?() }
        }
    }

    /// Called when a look-related setting changes so the menu bar redraws immediately
    /// (SwiftUI views update on their own via observation).
    @ObservationIgnored var onAppearanceChanged: (() -> Void)?

    /// Per-module notification threshold rules.
    var alertRules: [MetricID: AlertRule] {
        didSet { persistAlertRules() }
    }

    /// Per-module menu bar component (which look the module's item uses).
    var moduleComponents: [MetricID: MenuBarComponent] {
        didSet { persistModuleComponents(); onAppearanceChanged?() }
    }

    func component(for id: MetricID) -> MenuBarComponent {
        let chosen = moduleComponents[id] ?? .default(for: id)
        return MenuBarComponent.available(for: id).contains(chosen) ? chosen : .default(for: id)
    }

    private let defaults = UserDefaults.standard
    private static let enabledKey = "enabledModules"
    private static let floatingPanelKey = "showFloatingPanel"
    private static let onboardingKey = "hasCompletedOnboarding"
    private static let accentKey = "accentChoice"
    private static let alertsKey = "alertRules"
    private static let moduleComponentsKey = "moduleComponents"
    private static let legacyStylesKey = "moduleStyles"

    init() {
        let providers = MetricsKit.coreProviders()
        let available = providers.filter { $0.isAvailable }.map { $0.id }
        // Temperatures are not a standalone module: the sensors provider keeps
        // sampling in the background and its readings surface inside the CPU/GPU
        // popovers (hardware-domain grouping).
        self.availableModules = available.filter { $0 != .sensors }

        let engine = MetricsEngine()
        engine.register(providers)
        self.engine = engine

        self.showFloatingPanel = defaults.bool(forKey: Self.floatingPanelKey)
        self.hasCompletedOnboarding = defaults.bool(forKey: Self.onboardingKey)
        self.accentChoice = AccentChoice(rawValue: defaults.string(forKey: Self.accentKey) ?? "") ?? .system
        self.alertRules = Self.loadAlertRules(from: defaults, available: available)
        self.moduleComponents = Self.loadModuleComponents(from: defaults)

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

    // MARK: - Appearance

    /// Effective accent as an AppKit color (menu bar rendering).
    var accentNSColor: NSColor { accentChoice.nsColor ?? .controlAccentColor }

    /// Effective accent as a SwiftUI color (popover, floating panel).
    var accentColor: Color { Color(nsColor: accentNSColor) }

    // MARK: - Alerts

    /// Modules that support threshold alerts, in display order.
    var alertableModules: [MetricID] {
        availableModules.filter { alertRules[$0] != nil }
    }

    private static func defaultAlertRules(available: [MetricID]) -> [MetricID: AlertRule] {
        var rules: [MetricID: AlertRule] = [:]
        for id in available {
            switch id {
            case .cpu, .memory, .disk, .gpu:
                rules[id] = AlertRule(enabled: false, thresholdPercent: 90)
            case .battery:
                rules[id] = AlertRule(enabled: false, thresholdPercent: 20)
            default:
                break
            }
        }
        return rules
    }

    private static func loadAlertRules(from defaults: UserDefaults,
                                       available: [MetricID]) -> [MetricID: AlertRule] {
        var rules = defaultAlertRules(available: available)
        if let data = defaults.data(forKey: Self.alertsKey),
           let raw = try? JSONDecoder().decode([String: AlertRule].self, from: data) {
            for (key, rule) in raw {
                if let id = MetricID(rawValue: key), rules[id] != nil {
                    rules[id] = rule
                }
            }
        }
        return rules
    }

    private func persistAlertRules() {
        let raw = Dictionary(uniqueKeysWithValues: alertRules.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(raw) {
            defaults.set(data, forKey: Self.alertsKey)
        }
    }

    private static func loadModuleComponents(from defaults: UserDefaults) -> [MetricID: MenuBarComponent] {
        if let raw = defaults.dictionary(forKey: Self.moduleComponentsKey) as? [String: String] {
            var components: [MetricID: MenuBarComponent] = [:]
            for (key, value) in raw {
                if let id = MetricID(rawValue: key), let component = MenuBarComponent(rawValue: value) {
                    components[id] = component
                }
            }
            return components
        }
        // Migrate the short-lived value/graph/both style preference.
        if let legacy = defaults.dictionary(forKey: Self.legacyStylesKey) as? [String: String] {
            var components: [MetricID: MenuBarComponent] = [:]
            for (key, value) in legacy {
                guard let id = MetricID(rawValue: key) else { continue }
                switch value {
                case "value": components[id] = .value
                case "graph": components[id] = .graph
                case "both":  components[id] = .valueGraph
                default: break
                }
            }
            return components
        }
        return [:]
    }

    private func persistModuleComponents() {
        let raw = Dictionary(uniqueKeysWithValues: moduleComponents.map { ($0.key.rawValue, $0.value.rawValue) })
        defaults.set(raw, forKey: Self.moduleComponentsKey)
    }
}
