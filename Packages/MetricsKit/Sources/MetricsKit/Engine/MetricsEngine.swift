import Foundation

/// Metric collection coordinator.
///
/// - Periodically samples the registered providers on a serial background queue.
/// - Writes results into the `MetricStore` (ring buffer / history).
/// - Calls `onCycle` on the **main thread** after each cycle → UI update.
///
/// UI-agnostic (does not import SwiftUI); the CLI and the app share the same engine.
public final class MetricsEngine: @unchecked Sendable {
    public let store: MetricStore

    private var providers: [MetricProvider] = []
    private let queue = DispatchQueue(label: "com.mectrics.sampling", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var policy: SamplingPolicy
    private var cycleCount = 0
    /// `nil` samples every registered provider. The app sets an explicit subset so
    /// disabled modules do not consume power; the CLI keeps the default.
    private var activeMetricIDs: Set<MetricID>?

    /// Called on the main thread after each sampling cycle.
    /// Parameter: the latest values of the metrics updated this cycle.
    public var onCycle: (@MainActor @Sendable ([MetricID: MetricSample]) -> Void)?

    /// Called on the main thread after every cycle that attempted at least one
    /// provider. Unlike `onCycle`, this also reports failed attempts so clients can
    /// distinguish collecting, stale, and error states.
    public var onCycleReport: (@MainActor @Sendable (SamplingCycleReport) -> Void)?

    public init(store: MetricStore = MetricStore(),
                policy: SamplingPolicy = .default) {
        self.store = store
        self.policy = policy
    }

    /// Registers the available providers (unavailable ones are dropped).
    public func register(_ providers: [MetricProvider]) {
        queue.async { [weak self] in
            guard let self else { return }
            self.providers = providers.filter { $0.isAvailable }
        }
    }

    /// Restricts sampling to the supplied metrics. Pass `nil` to sample all providers.
    public func setActiveMetrics(_ ids: Set<MetricID>?) {
        queue.async { [weak self] in
            self?.activeMetricIDs = ids
        }
    }

    public func start(onBattery: Bool = false) {
        queue.async { [weak self] in
            guard let self else { return }
            self.scheduleTimer(onBattery: onBattery)
        }
    }

    public func stop() {
        queue.async { [weak self] in
            self?.timer?.cancel()
            self?.timer = nil
        }
    }

    /// Requests an immediate pass on the serial sampling queue.
    public func requestRefresh() {
        queue.async { [weak self] in
            self?.tick()
        }
    }

    /// Re-tunes the interval when the power state changes.
    public func updatePowerState(onBattery: Bool) {
        queue.async { [weak self] in
            guard let self, self.timer != nil else { return }
            self.scheduleTimer(onBattery: onBattery)
        }
    }

    private func scheduleTimer(onBattery: Bool) {
        timer?.cancel()
        let interval = onBattery ? policy.onBatteryInterval : policy.onACInterval
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(100))
        t.setEventHandler { [weak self] in
            self?.tick()
        }
        timer = t
        t.resume()
    }

    private func tick() {
        cycleCount &+= 1
        let runHeavy = cycleCount % max(1, policy.heavyEveryNCycles) == 0
        var updated: [MetricID: MetricSample] = [:]
        var failed: Set<MetricID> = []
        var attemptedAnyProvider = false

        for provider in providers {
            if let activeMetricIDs, !activeMetricIDs.contains(provider.id) { continue }
            if provider.cost == .heavy && !runHeavy { continue }
            attemptedAnyProvider = true
            if let sample = provider.sample() {
                store.append(sample, for: provider.id)
                updated[provider.id] = sample
            } else {
                failed.insert(provider.id)
            }
        }

        guard attemptedAnyProvider else { return }
        let report = SamplingCycleReport(
            samples: updated,
            failedMetricIDs: failed
        )
        Task { @MainActor [onCycle, onCycleReport] in
            if !updated.isEmpty {
                onCycle?(updated)
            }
            onCycleReport?(report)
        }
    }
}
