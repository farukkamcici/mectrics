import Foundation
import MetricsKit

struct OneShotSamplingResult: Sendable {
    let samples: [MetricID: MetricSample]
    let unavailableMetricIDs: Set<MetricID>
    let failedMetricIDs: Set<MetricID>
    let timedOut: Bool
}

typealias ProviderFactory = @Sendable (Set<MetricID>) -> [MetricProvider]

@MainActor
final class OneShotSampler {
    private let providerFactory: ProviderFactory
    private let timeout: Duration
    private let engine = MetricsEngine()

    private var availableMetricIDs: Set<MetricID> = []
    private var unavailableMetricIDs: Set<MetricID> = []
    private var latest: [MetricID: MetricSample] = [:]
    private var attempts = 0
    private var completed = false
    private var continuation: CheckedContinuation<OneShotSamplingResult, Never>?
    private var timeoutTask: Task<Void, Never>?

    init(
        providerFactory: @escaping ProviderFactory = MetricsKit.coreProviders(for:),
        timeout: Duration = .seconds(6)
    ) {
        self.providerFactory = providerFactory
        self.timeout = timeout
    }

    func sample(_ requestedMetricIDs: Set<MetricID>) async -> OneShotSamplingResult {
        let providers = providerFactory(requestedMetricIDs)
        let availableProviders = providers.filter(\.isAvailable)
        availableMetricIDs = Set(availableProviders.map(\.id))
        unavailableMetricIDs = requestedMetricIDs.subtracting(availableMetricIDs)

        guard !availableProviders.isEmpty else {
            return OneShotSamplingResult(
                samples: [:],
                unavailableMetricIDs: unavailableMetricIDs,
                failedMetricIDs: [],
                timedOut: false
            )
        }

        engine.register(availableProviders, alreadyFiltered: true)
        engine.setActiveMetrics(availableMetricIDs)
        engine.onCycleReport = { [weak self] report in
            self?.received(report)
        }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            requestSample()
            timeoutTask = Task { @MainActor [weak self, timeout] in
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                self?.finish(timedOut: true)
            }
        }
    }

    private func requestSample() {
        guard !completed else { return }
        attempts += 1
        engine.requestRefresh(includingHeavy: true)
    }

    private func received(_ report: SamplingCycleReport) {
        latest.merge(report.samples) { _, new in new }
        let missing = availableMetricIDs.subtracting(latest.keys)
        if missing.isEmpty || attempts >= 3 {
            finish(timedOut: false)
        } else {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(250))
                self?.requestSample()
            }
        }
    }

    private func finish(timedOut: Bool) {
        guard !completed else { return }
        completed = true
        timeoutTask?.cancel()
        timeoutTask = nil
        engine.stop()
        let result = OneShotSamplingResult(
            samples: latest,
            unavailableMetricIDs: unavailableMetricIDs,
            failedMetricIDs: availableMetricIDs.subtracting(latest.keys),
            timedOut: timedOut
        )
        continuation?.resume(returning: result)
        continuation = nil
    }
}
