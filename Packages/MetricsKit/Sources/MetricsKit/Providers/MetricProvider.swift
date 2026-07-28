import Foundation

/// Contract implemented by every metric source.
///
/// Providers may hold state (e.g. CPU/network need the delta between two consecutive
/// samples), hence `class` (reference type). Sampling always happens on the same serial
/// queue, so providers need not be thread-safe; therefore `@unchecked Sendable`.
public protocol MetricProvider: AnyObject {
    var id: MetricID { get }

    /// Is this hardware/permission available on this machine?
    /// (e.g. a fanless MacBook Air has no fans.)
    var isAvailable: Bool { get }

    /// Cost class used by the scheduler to decide sampling frequency.
    var cost: SamplingCost { get }

    /// A single sample. Returns `nil` on failure (no hardware / transient error).
    func sample() -> MetricSample?
}

public extension MetricProvider {
    var isAvailable: Bool { true }
    var cost: SamplingCost { .light }
}
