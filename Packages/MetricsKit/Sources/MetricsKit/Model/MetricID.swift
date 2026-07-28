import Foundation

/// Stable identity of every metric module in the app.
/// UI, settings and App Group snapshots are keyed by these values.
public enum MetricID: String, CaseIterable, Codable, Sendable {
    case cpu
    case memory
    case battery
    case network
    case disk
    case gpu
    case sensors
    case fans
    case bluetooth
    case clock

    /// Short, developer-facing (English) name. User-facing localized names are
    /// provided at the app layer (see `MetricID.localizedName`); this value is the
    /// English development-language fallback.
    public var displayName: String {
        switch self {
        case .cpu: return "CPU"
        case .memory: return "Memory"
        case .battery: return "Battery"
        case .network: return "Network"
        case .disk: return "Disk"
        case .gpu: return "GPU"
        case .sensors: return "Sensors"
        case .fans: return "Fans"
        case .bluetooth: return "Bluetooth"
        case .clock: return "Clock"
        }
    }
}

/// Sampling cost of a provider — the scheduler uses this to decide frequency.
public enum SamplingCost: Sendable {
    case light   // cheap host_statistics-style calls (CPU, RAM)
    case medium  // IOKit queries (battery, disk, network)
    case heavy   // SMC / sensors / GPU — sampled less often
}
