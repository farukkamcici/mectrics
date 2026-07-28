import Foundation

/// Result of one scheduler pass.
///
/// Heavy or inactive providers that were intentionally skipped are absent from both
/// collections. A failed metric is one whose provider was attempted but returned no
/// sample.
public struct SamplingCycleReport: Sendable {
    public let samples: [MetricID: MetricSample]
    public let failedMetricIDs: Set<MetricID>

    public init(
        samples: [MetricID: MetricSample],
        failedMetricIDs: Set<MetricID>
    ) {
        self.samples = samples
        self.failedMetricIDs = failedMetricIDs
    }
}
