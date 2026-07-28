import Foundation

/// Tek bir örnekleme anındaki metrik değeri.
///
/// - `value`: 0...1 aralığında normalize edilmiş temel değer (ör. CPU kullanımı 0.42).
///   Yüzde göstermek için `* 100`. Hız/sıcaklık gibi normalize edilemeyen metriklerde
///   `value` ham değeri taşır ve yorumu `unit` belirler.
/// - `detail`: modüle özgü ayrıntılar (per-core, used/wired, up/down bytes, °C ...).
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

    /// Sparkline/istatistik için 0...1 aralığına oturtulmuş değer.
    /// `.fraction` ise value; `.percent` ise value/100; diğerlerinde value olduğu gibi
    /// döner (grafik kendi min/max'ını normalize eder).
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
    case bytesPerSecond  // ağ/disk hız
    case bytes           // kapasite
    case celsius         // sıcaklık
    case rpm             // fan
    case watts           // güç
    case count           // adet (cycle, cihaz sayısı)
}
