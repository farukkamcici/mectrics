import Foundation

/// Data-quality state shared by every Mectrics presentation surface.
///
/// This type intentionally contains no localized copy or UI styling. The app and
/// widget translate it into their native presentation language.
public enum MetricDataState: String, CaseIterable, Codable, Sendable {
    case collecting
    case live
    case unavailable
    case disabled
    case permissionRequired
    case stale
    case error

    /// Resolves a deterministic state without fabricating a sample.
    ///
    /// A short provider interruption preserves the last valid sample. Three
    /// consecutive failed attempts promote the state to `error`; an old sample with
    /// no explicit failure is `stale`.
    public static func resolve(
        isAvailable: Bool,
        isEnabled: Bool,
        sample: MetricSample?,
        consecutiveFailures: Int = 0,
        requiresPermission: Bool = false,
        now: Date = Date(),
        staleAfter: TimeInterval = 15
    ) -> MetricDataState {
        guard isAvailable else { return .unavailable }
        guard isEnabled else { return .disabled }
        guard !requiresPermission else { return .permissionRequired }
        if consecutiveFailures >= 3 { return .error }
        guard let sample else { return .collecting }
        if now.timeIntervalSince(sample.timestamp) > staleAfter { return .stale }
        return .live
    }
}
