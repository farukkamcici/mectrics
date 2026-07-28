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

    /// Enabled menu bar items: per module, which components are shown. A module may
    /// contribute several items at once (e.g. Battery icon + Battery health).
    var enabledComponents: [MetricID: Set<MenuBarComponent>] {
        didSet {
            persistEnabledComponents()
            if enabledComponents != oldValue { onModulesChanged?() }
        }
    }

    /// Modules with at least one component in the menu bar (popover/panel scope).
    var enabledModules: Set<MetricID> {
        Set(availableModules.filter { !(enabledComponents[$0] ?? []).isEmpty })
    }

    /// Menu bar items in display order: module order, then the component order
    /// defined by `MenuBarComponent.available(for:)`.
    var orderedEnabledItems: [(module: MetricID, component: MenuBarComponent)] {
        availableModules.flatMap { id in
            MenuBarComponent.available(for: id)
                .filter { enabledComponents[id]?.contains($0) ?? false }
                .map { (id, $0) }
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

    func isComponentEnabled(_ component: MenuBarComponent, for id: MetricID) -> Bool {
        enabledComponents[id]?.contains(component) ?? false
    }

    func toggleComponent(_ component: MenuBarComponent, for id: MetricID) {
        var set = enabledComponents[id] ?? []
        if set.contains(component) { set.remove(component) } else { set.insert(component) }
        enabledComponents[id] = set
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
        self.enabledComponents = Self.loadEnabledComponents(
            from: defaults, available: available.filter { $0 != .sensors })
    }

    /// Modules in menu bar order (CPU, Memory, Battery ...).
    var orderedEnabledModules: [MetricID] {
        availableModules.filter { enabledModules.contains($0) }
    }

    /// Module-level switch (onboarding): enabling adds the default component if the
    /// module has none; disabling removes all of its components.
    func setEnabled(_ enabled: Bool, for id: MetricID) {
        if enabled {
            if (enabledComponents[id] ?? []).isEmpty {
                enabledComponents[id] = [.default(for: id)]
            }
        } else {
            enabledComponents[id] = []
        }
    }

    /// Normalized history for sparklines.
    func history(_ id: MetricID, count: Int = 40) -> [Double] {
        engine.store.history(id, count: count).map(\.normalized)
    }

    private static let enabledComponentsKey = "enabledComponents"

    private static func loadEnabledComponents(from defaults: UserDefaults,
                                              available: [MetricID]) -> [MetricID: Set<MenuBarComponent>] {
        if let data = defaults.data(forKey: Self.enabledComponentsKey),
           let raw = try? JSONDecoder().decode([String: [String]].self, from: data) {
            var result: [MetricID: Set<MenuBarComponent>] = [:]
            for (key, values) in raw {
                guard let id = MetricID(rawValue: key), available.contains(id) else { continue }
                let valid = MenuBarComponent.available(for: id)
                result[id] = Set(values.compactMap(MenuBarComponent.init).filter(valid.contains))
            }
            return result
        }
        // Migrate the one-component-per-module era (enabledModules + moduleComponents).
        let legacyChoices = Self.loadModuleComponents(from: defaults)
        let legacyEnabled: [MetricID]
        if let raw = defaults.array(forKey: Self.enabledKey) as? [String] {
            legacyEnabled = raw.compactMap { MetricID(rawValue: $0) }.filter(available.contains)
        } else {
            legacyEnabled = available
        }
        var result: [MetricID: Set<MenuBarComponent>] = [:]
        for id in (legacyEnabled.isEmpty ? available : legacyEnabled) {
            let choice = legacyChoices[id] ?? .default(for: id)
            result[id] = [MenuBarComponent.available(for: id).contains(choice) ? choice : .default(for: id)]
        }
        return result
    }

    private func persistEnabledComponents() {
        let raw = Dictionary(uniqueKeysWithValues: enabledComponents.map { key, value in
            (key.rawValue, value.map(\.rawValue).sorted())
        })
        if let data = try? JSONEncoder().encode(raw) {
            defaults.set(data, forKey: Self.enabledComponentsKey)
        }
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

    /// Legacy single-choice-per-module preference, read only for migration.
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
}
