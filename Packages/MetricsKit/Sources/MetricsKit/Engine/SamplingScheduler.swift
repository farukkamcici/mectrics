import Foundation

/// Determines the sampling interval based on power state.
/// Lightweight promise: faster on AC, slower on battery; sleep/visibility pausing
/// will be added later.
public struct SamplingPolicy: Sendable {
    /// Base interval while on AC power (seconds).
    public var onACInterval: TimeInterval
    /// Interval while on battery (seconds).
    public var onBatteryInterval: TimeInterval
    /// Heavy providers (sensors/GPU) are sampled once every N base cycles.
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
