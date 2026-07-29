import MetricsKit

/// The one SF Symbol per module, shared by every surface that shows a module
/// identity: menu bar items, detail popovers, the menu bar builder, Compact Health,
/// and onboarding.
enum MetricSymbol {
    static func name(for id: MetricID) -> String {
        switch id {
        case .cpu:       return "cpu"
        case .memory:    return "memorychip"
        case .battery:   return "battery.100percent"
        case .network:   return "arrow.up.arrow.down"
        case .disk:      return "internaldrive"
        case .bluetooth: return "wave.3.right"
        case .gpu:       return "rectangle.on.rectangle"
        case .sensors:   return "thermometer.medium"
        case .fans:      return "fan"
        case .clock:     return "clock"
        }
    }
}
