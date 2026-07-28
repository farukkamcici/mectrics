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

    /// Called on the main thread after each sampling cycle.
    /// Parameter: the latest values of the metrics updated this cycle.
    public var onCycle: (@Sendable ([MetricID: MetricSample]) -> Void)?

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

        for provider in providers {
            if provider.cost == .heavy && !runHeavy { continue }
            if let sample = provider.sample() {
                store.append(sample, for: provider.id)
                updated[provider.id] = sample
            }
        }

        DispatchQueue.main.async { [onCycle] in
            onCycle?(updated)
        }
    }
}
