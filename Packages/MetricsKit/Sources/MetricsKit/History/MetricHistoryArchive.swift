import Foundation

/// One downsampled primary metric value. Hourly averages keep a month compact.
public struct HistoricalMetricPoint: Codable, Sendable, Equatable {
    public let timestamp: Date
    public let average: Double
    public let minimum: Double
    public let maximum: Double
    public let unit: MetricUnit
    public let sampleCount: Int

    public init(
        timestamp: Date,
        average: Double,
        minimum: Double,
        maximum: Double,
        unit: MetricUnit,
        sampleCount: Int
    ) {
        self.timestamp = timestamp
        self.average = average
        self.minimum = minimum
        self.maximum = maximum
        self.unit = unit
        self.sampleCount = sampleCount
    }

    private enum CodingKeys: String, CodingKey {
        case timestamp
        case average
        case minimum
        case maximum
        case unit
        case sampleCount
        case value
    }

    /// Migrates the original average-only archive without discarding user data.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        unit = try container.decode(MetricUnit.self, forKey: .unit)
        let legacyValue = try container.decodeIfPresent(Double.self, forKey: .value)
        average = try container.decodeIfPresent(Double.self, forKey: .average)
            ?? legacyValue ?? 0
        minimum = try container.decodeIfPresent(Double.self, forKey: .minimum) ?? average
        maximum = try container.decodeIfPresent(Double.self, forKey: .maximum) ?? average
        sampleCount = try container.decodeIfPresent(Int.self, forKey: .sampleCount) ?? 1
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(average, forKey: .average)
        try container.encode(minimum, forKey: .minimum)
        try container.encode(maximum, forKey: .maximum)
        try container.encode(unit, forKey: .unit)
        try container.encode(sampleCount, forKey: .sampleCount)
    }
}

public struct MetricHistoryArchive: Codable, Sendable, Equatable {
    public private(set) var points: [MetricID: [HistoricalMetricPoint]]

    public init(points: [MetricID: [HistoricalMetricPoint]] = [:]) {
        self.points = points
    }

    public mutating func upsert(
        _ point: HistoricalMetricPoint,
        for id: MetricID,
        retention: TimeInterval = 30 * 24 * 60 * 60,
        now: Date = Date()
    ) {
        var metricPoints = points[id] ?? []
        if let index = metricPoints.firstIndex(where: { $0.timestamp == point.timestamp }) {
            metricPoints[index] = point
        } else {
            metricPoints.append(point)
            metricPoints.sort { $0.timestamp < $1.timestamp }
        }
        let cutoff = now.addingTimeInterval(-retention)
        points[id] = metricPoints.filter { $0.timestamp >= cutoff }
    }

    public func points(
        for id: MetricID,
        since cutoff: Date
    ) -> [HistoricalMetricPoint] {
        (points[id] ?? []).filter { $0.timestamp >= cutoff }
    }

    public func csvData() -> Data {
        var lines = ["hour,module,average,minimum,maximum,unit,samples"]
        let formatter = ISO8601DateFormatter()
        let locale = Locale(identifier: "en_US_POSIX")
        for id in MetricID.allCases {
            for point in points[id] ?? [] {
                let scale = point.unit == .fraction ? 100.0 : 1.0
                let exportedUnit = point.unit == .fraction ? "percent" : point.unit.rawValue
                lines.append([
                    formatter.string(from: point.timestamp),
                    id.displayName,
                    String(format: "%.2f", locale: locale, point.average * scale),
                    String(format: "%.2f", locale: locale, point.minimum * scale),
                    String(format: "%.2f", locale: locale, point.maximum * scale),
                    exportedUnit,
                    String(point.sampleCount)
                ].joined(separator: ","))
            }
        }
        return Data((lines.joined(separator: "\n") + "\n").utf8)
    }
}

public struct MetricHistoryArchiveStore: Sendable {
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func applicationSupportStore() -> Self {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return Self(fileURL: base
            .appendingPathComponent("Mectrics", isDirectory: true)
            .appendingPathComponent("metric-history.json"))
    }

    public func read() throws -> MetricHistoryArchive {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(
            MetricHistoryArchive.self,
            from: Data(contentsOf: fileURL)
        )
    }

    public func write(_ archive: MetricHistoryArchive) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        try encoder.encode(archive).write(to: fileURL, options: .atomic)
    }
}
