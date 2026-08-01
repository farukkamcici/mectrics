import Foundation

/// One current reading exposed by the read-only automation interface.
public struct MetricSnapshotReading: Codable, Equatable, Sendable {
    public let metric: MetricID
    public let timestamp: Date
    public let value: Double
    public let unit: MetricUnit
    public let detail: [String: Double]

    public init(metric: MetricID, sample: MetricSample) {
        self.metric = metric
        timestamp = sample.timestamp
        value = sample.value
        unit = sample.unit
        detail = sample.detail
    }
}

/// A versioned, one-shot snapshot of every metric available on this Mac.
public struct MetricSnapshotReport: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let timestamp: Date
    public let metrics: [MetricSnapshotReading]
    public let unavailable: [MetricID]

    public init(
        latest: [MetricID: MetricSample],
        requested: Set<MetricID> = Set(MetricID.allCases),
        timestamp: Date = Date()
    ) {
        schemaVersion = 1
        self.timestamp = timestamp
        metrics = MetricID.allCases.compactMap { metric in
            guard requested.contains(metric),
                  let sample = latest[metric]
            else { return nil }
            return MetricSnapshotReading(metric: metric, sample: sample)
        }
        unavailable = MetricID.allCases.filter {
            requested.contains($0) && latest[$0] == nil
        }
    }
}
