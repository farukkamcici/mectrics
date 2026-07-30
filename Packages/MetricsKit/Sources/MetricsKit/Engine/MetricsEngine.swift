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
    private var runtimePolicy: SamplingRuntimePolicy
    private var onBattery = false
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
        self.runtimePolicy = SamplingRuntimePolicy(
            mediumEveryNCycles: policy.mediumEveryNCycles,
            heavyEveryNCycles: policy.heavyEveryNCycles
        )
    }

    /// Registers the available providers (unavailable ones are dropped).
    ///
    /// Pass `alreadyFiltered: true` when the caller has taken its own availability
    /// pass. Probing costs real work for hardware-backed providers, and asking twice
    /// on launch delays the first reading for no gain.
    public func register(
        _ providers: [MetricProvider],
        alreadyFiltered: Bool = false
    ) {
        queue.async { [weak self] in
            guard let self else { return }
            self.providers = alreadyFiltered
                ? providers
                : providers.filter { $0.isAvailable }
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
            self.onBattery = onBattery
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
    /// Samples every active provider immediately.
    ///
    /// `includingHeavy` overrides the runtime policy's slowdown and pausing, which
    /// exists to save energy in the background. When the user explicitly asks for a
    /// reading, returning stale sensor or GPU values would answer a different
    /// question than the one they asked.
    public func requestRefresh(includingHeavy: Bool = false) {
        queue.async { [weak self] in
            self?.tick(forcingAllProviders: includingHeavy)
        }
    }

    /// Re-tunes the interval when the power state changes.
    public func updatePowerState(onBattery: Bool) {
        queue.async { [weak self] in
            guard let self, self.timer != nil else { return }
            self.onBattery = onBattery
            self.scheduleTimer(onBattery: onBattery)
        }
    }

    /// Applies an Energy Guard overlay and re-tunes the timer immediately.
    public func updateRuntimePolicy(_ runtimePolicy: SamplingRuntimePolicy) {
        queue.async { [weak self] in
            guard let self else { return }
            self.runtimePolicy = runtimePolicy
            if self.timer != nil {
                self.scheduleTimer(onBattery: self.onBattery)
            }
        }
    }

    private func scheduleTimer(onBattery: Bool) {
        timer?.cancel()
        let baseInterval =
            onBattery ? policy.onBatteryInterval : policy.onACInterval
        let interval = baseInterval * runtimePolicy.intervalMultiplier
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(100))
        t.setEventHandler { [weak self] in
            self?.tick()
        }
        timer = t
        t.resume()
    }

    private func tick(forcingAllProviders: Bool = false) {
        cycleCount &+= 1
        let runMedium = forcingAllProviders
            || cycleCount % max(1, runtimePolicy.mediumEveryNCycles) == 0
        let runHeavy = forcingAllProviders
            || cycleCount % max(1, runtimePolicy.heavyEveryNCycles) == 0
        var updated: [MetricID: MetricSample] = [:]
        var failed: Set<MetricID> = []
        var attemptedAnyProvider = false

        for provider in providers {
            if let activeMetricIDs, !activeMetricIDs.contains(provider.id) { continue }
            if !forcingAllProviders,
               runtimePolicy.pausedMetricIDs.contains(provider.id) { continue }
            if provider.cost == .medium && !runMedium { continue }
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
