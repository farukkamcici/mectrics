import Foundation
import MetricsKit

/// Aggregates live samples into hourly averages and persists a rolling 30-day archive.
@MainActor
final class HistoryRecorder {
    private struct Bucket {
        let timestamp: Date
        let unit: MetricUnit
        var sum: Double
        var count: Int
        var minimum: Double
        var maximum: Double

        var point: HistoricalMetricPoint {
            HistoricalMetricPoint(
                timestamp: timestamp,
                average: sum / Double(max(count, 1)),
                minimum: minimum,
                maximum: maximum,
                unit: unit,
                sampleCount: count
            )
        }
    }

    private let store = MetricHistoryArchiveStore.applicationSupportStore()
    private let writerQueue = DispatchQueue(label: "com.mectrics.metric-history", qos: .utility)
    private var archive: MetricHistoryArchive
    private var buckets: [MetricID: Bucket] = [:]
    private var lastCheckpoint = Date.distantPast

    init() {
        archive = (try? store.read()) ?? MetricHistoryArchive()
    }

    func record(_ samples: [MetricID: MetricSample], now: Date = Date()) {
        let hour = Self.startOfHour(now)
        for (id, sample) in samples {
            let measurement = Self.measurement(for: id, sample: sample)
            if var bucket = buckets[id],
               bucket.timestamp == hour,
               bucket.unit == measurement.unit {
                bucket.sum += measurement.value
                bucket.count += 1
                bucket.minimum = min(bucket.minimum, measurement.value)
                bucket.maximum = max(bucket.maximum, measurement.value)
                buckets[id] = bucket
            } else {
                if let previous = buckets[id] {
                    archive.upsert(previous.point, for: id, now: now)
                }
                buckets[id] = Bucket(
                    timestamp: hour,
                    unit: measurement.unit,
                    sum: measurement.value,
                    count: 1,
                    minimum: measurement.value,
                    maximum: measurement.value
                )
            }
        }
        if now.timeIntervalSince(lastCheckpoint) >= 5 * 60 {
            checkpoint(now: now)
        }
    }

    func checkpoint(now: Date = Date()) {
        let snapshot = materializedArchive(now: now)
        lastCheckpoint = now
        let store = store
        writerQueue.async {
            try? store.write(snapshot)
        }
    }

    func csvData(now: Date = Date()) -> Data {
        materializedArchive(now: now).csvData()
    }

    func points(
        for id: MetricID,
        since cutoff: Date,
        now: Date = Date()
    ) -> [HistoricalMetricPoint] {
        materializedArchive(now: now).points(for: id, since: cutoff)
    }

    private func materializedArchive(now: Date) -> MetricHistoryArchive {
        var snapshot = archive
        for (id, bucket) in buckets {
            snapshot.upsert(bucket.point, for: id, now: now)
        }
        return snapshot
    }

    private static func startOfHour(_ date: Date) -> Date {
        Date(timeIntervalSince1970: floor(date.timeIntervalSince1970 / 3_600) * 3_600)
    }

    /// Some providers use `value` as a normalized availability signal while their
    /// useful user-facing measurement lives in detail.
    private static func measurement(
        for id: MetricID,
        sample: MetricSample
    ) -> (value: Double, unit: MetricUnit) {
        switch id {
        case .network:
            return (
                (sample.detail["down"] ?? 0) + (sample.detail["up"] ?? 0),
                .bytesPerSecond
            )
        case .fans:
            return (sample.detail["maxRpm"] ?? 0, .rpm)
        default:
            return (sample.value, sample.unit)
        }
    }
}
