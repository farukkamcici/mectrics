import Foundation

/// Determines the sampling interval based on power state.
/// Lightweight promise: faster on AC, slower on battery; sleep/visibility pausing
/// will be added later.
public struct SamplingPolicy: Sendable {
    /// Base interval while on AC power (seconds).
    public var onACInterval: TimeInterval
    /// Interval while on battery (seconds).
    public var onBatteryInterval: TimeInterval
    /// Medium providers (battery, disk) are sampled once every N base cycles.
    public var mediumEveryNCycles: Int
    /// Heavy providers (sensors/GPU) are sampled once every N base cycles.
    public var heavyEveryNCycles: Int

    public init(
        onACInterval: TimeInterval = 1.0,
        onBatteryInterval: TimeInterval = 2.0,
        mediumEveryNCycles: Int = 1,
        heavyEveryNCycles: Int = 3
    ) {
        self.onACInterval = onACInterval
        self.onBatteryInterval = onBatteryInterval
        self.mediumEveryNCycles = mediumEveryNCycles
        self.heavyEveryNCycles = heavyEveryNCycles
    }

    public static let `default` = SamplingPolicy()
}

/// Runtime overlay used by the app to reduce its own work without changing which
/// metrics the user selected. Low-cost providers remain eligible on every base cycle;
/// expensive providers can be slowed or temporarily paused.
public struct SamplingRuntimePolicy: Sendable, Equatable {
    public var intervalMultiplier: Double
    public var mediumEveryNCycles: Int
    public var heavyEveryNCycles: Int
    public var pausedMetricIDs: Set<MetricID>

    public init(
        intervalMultiplier: Double = 1,
        mediumEveryNCycles: Int = 1,
        heavyEveryNCycles: Int = 3,
        pausedMetricIDs: Set<MetricID> = []
    ) {
        self.intervalMultiplier = max(intervalMultiplier, 1)
        self.mediumEveryNCycles = max(mediumEveryNCycles, 1)
        self.heavyEveryNCycles = max(heavyEveryNCycles, 1)
        self.pausedMetricIDs = pausedMetricIDs
    }

    public static let normal = SamplingRuntimePolicy()
}
