import Foundation

/// A metric value captured at a single sampling instant.
///
/// - `value`: normalized base value in 0...1 (e.g. CPU usage 0.42). Multiply by 100 for
///   a percentage. For metrics that cannot be normalized (rate/temperature), `value`
///   carries the raw value and `unit` describes its interpretation.
/// - `detail`: module-specific breakdown (per-core, used/wired, up/down bytes, °C ...).
public struct MetricSample: Sendable, Codable, Equatable {
    public let timestamp: Date
    public let value: Double
    public let unit: MetricUnit
    public let detail: [String: Double]

    public init(
        timestamp: Date = Date(),
        value: Double,
        unit: MetricUnit = .fraction,
        detail: [String: Double] = [:]
    ) {
        self.timestamp = timestamp
        self.value = value
        self.unit = unit
        self.detail = detail
    }

    /// Value mapped into 0...1 for sparklines/stats.
    /// `.fraction` -> value; `.percent` -> value/100; otherwise value as-is
    /// (the chart normalizes against its own min/max).
    public var normalized: Double {
        switch unit {
        case .fraction: return value
        case .percent: return value / 100
        default: return value
        }
    }
}

public enum MetricUnit: String, Sendable, Codable {
    case fraction        // 0...1
    case percent         // 0...100
    case bytesPerSecond  // network/disk rate
    case bytes           // capacity
    case celsius         // temperature
    case rpm             // fan
    case watts           // power
    case count           // count (cycles, device count)
}
