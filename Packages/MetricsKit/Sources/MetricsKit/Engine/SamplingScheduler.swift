import Foundation

/// Güç durumuna göre örnekleme aralığını belirler.
/// Hafiflik sözü: AC'de hızlı, pilde yavaş; ileride uyku/görünürlük ile duraklatma eklenir.
public struct SamplingPolicy: Sendable {
    /// AC güç kaynağındayken temel aralık (sn).
    public var onACInterval: TimeInterval
    /// Pildeyken aralık (sn).
    public var onBatteryInterval: TimeInterval
    /// Ağır provider'lar (sensör/GPU) kaç temel döngüde bir örneklensin.
    public var heavyEveryNCycles: Int

    public init(
        onACInterval: TimeInterval = 1.0,
        onBatteryInterval: TimeInterval = 2.0,
        heavyEveryNCycles: Int = 3
    ) {
        self.onACInterval = onACInterval
        self.onBatteryInterval = onBatteryInterval
        self.heavyEveryNCycles = heavyEveryNCycles
    }

    public static let `default` = SamplingPolicy()
}
