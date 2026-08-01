import Foundation
import MetricsKit

// MARK: - Internationalization (i18n)
//
// The app is English-first but built to be localizable. All user-facing strings go
// through `String(localized:)` (or SwiftUI `Text`/`Label`, which localize automatically),
// so they are extracted into `Resources/Localizable.xcstrings` (String Catalog) at build
// time. A supported language is represented in both String Catalogs and in `AppLanguage`,
// which powers the in-app language picker.
//
// MetricsKit stays localization-free (data-only); user-facing module names are provided
// here at the app layer.

enum AppLocalization {
    /// Returns a language-specific resource bundle when a caller needs deterministic
    /// localized output, such as a test fixture. Normal app UI uses `Bundle.main`.
    static func bundle(for locale: Locale?) -> Bundle {
        guard let locale else { return .main }
        let identifier = locale.identifier.replacingOccurrences(of: "_", with: "-")
        let candidates = [
            identifier,
            identifier.split(separator: "-").first.map(String.init)
        ].compactMap { $0 }

        for candidate in candidates {
            if let url = Bundle.main.url(
                forResource: candidate,
                withExtension: "lproj"
            ), let bundle = Bundle(url: url) {
                return bundle
            }
        }
        return .main
    }
}

extension ThermalPressureLevel {
    /// How much the Mac is being held back, in words a person can act on.
    ///
    /// Apple's own names — nominal, fair, serious, critical — describe the thermal
    /// situation. What someone actually notices is how much slower their machine has
    /// become, so the scale is named for that instead.
    var localizedName: String {
        switch self {
        case .nominal:
            return String(localized: "thermal.nominal", defaultValue: "None")
        case .fair:
            return String(localized: "thermal.fair", defaultValue: "Light")
        case .serious:
            return String(localized: "thermal.serious", defaultValue: "Noticeable")
        case .critical:
            return String(localized: "thermal.critical", defaultValue: "Severe")
        }
    }
}

extension MemoryPressureLevel {
    /// Activity Monitor's own vocabulary for the same kernel value, so the two agree
    /// when someone opens both.
    var localizedName: String {
        switch self {
        case .normal:
            return String(localized: "pressure.normal", defaultValue: "Normal")
        case .warning:
            return String(localized: "pressure.warning", defaultValue: "Warning")
        case .critical:
            return String(localized: "pressure.critical", defaultValue: "Critical")
        }
    }
}

/// Every alert condition travels through the pipeline as one `Double`, so the level
/// words are resolved back from that value here rather than in each surface.
enum SystemSignalFormat {
    static func thermal(_ value: Double) -> String {
        let clamped = min(
            max(Int(value), ThermalPressureLevel.nominal.rawValue),
            ThermalPressureLevel.critical.rawValue
        )
        return (ThermalPressureLevel(rawValue: clamped) ?? .nominal).localizedName
    }

    /// The kernel's levels skip 3; anything it does not define reads as normal.
    static func pressure(_ value: Double) -> String {
        (MemoryPressureLevel(rawValue: Int(value)) ?? .normal).localizedName
    }
}

extension MetricID {
    /// Localized, user-facing module name (English is the development-language default).
    var localizedName: String {
        switch self {
        case .cpu:       return String(localized: "module.cpu", defaultValue: "CPU")
        case .memory:    return String(localized: "module.memory", defaultValue: "Memory")
        case .battery:   return String(localized: "module.battery", defaultValue: "Battery")
        case .network:   return String(localized: "module.network", defaultValue: "Network")
        case .disk:      return String(localized: "module.disk", defaultValue: "Disk")
        case .gpu:       return String(localized: "module.gpu", defaultValue: "GPU")
        case .sensors:   return String(localized: "module.sensors", defaultValue: "Sensors")
        case .fans:      return String(localized: "module.fans", defaultValue: "Fans")
        }
    }
}
