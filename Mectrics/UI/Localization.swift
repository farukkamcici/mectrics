import Foundation
import MetricsKit

// MARK: - Internationalization (i18n)
//
// The app is English-first but built to be localizable. All user-facing strings go
// through `String(localized:)` (or SwiftUI `Text`/`Label`, which localize automatically),
// so they are extracted into `Resources/Localizable.xcstrings` (String Catalog) at build
// time. To add a language, open the catalog in Xcode, add the language, and translate the
// entries — no code changes required.
//
// MetricsKit stays localization-free (data-only); user-facing module names are provided
// here at the app layer.

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
        case .bluetooth: return String(localized: "module.bluetooth", defaultValue: "Bluetooth")
        case .clock:     return String(localized: "module.clock", defaultValue: "Clock")
        }
    }
}
