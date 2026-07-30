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
