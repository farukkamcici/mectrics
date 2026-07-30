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
        }
    }
}

/// Sampling cost of a provider — the scheduler uses this to decide frequency.
/// Sampling cost of a provider. The scheduler samples `.light` on every base cycle and
/// thins `.medium` and `.heavy` by the intervals in `SamplingRuntimePolicy`, so a
/// provider's class decides how often it actually runs.
public enum SamplingCost: Sendable {
    case light   // cheap syscalls (CPU, memory, network counters)
    case medium  // IOKit queries (battery, disk)
    case heavy   // SMC / sensors / GPU — sampled less often
}
