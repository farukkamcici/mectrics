import Foundation

/// A compact, Codable handoff from the live app to low-frequency consumers such as
/// WidgetKit. Histories contain normalized values ready for sparkline rendering.
public struct SharedMetricSnapshot: Codable, Sendable, Equatable {
    public let generatedAt: Date
    public let orderedMetricIDs: [MetricID]
    public let samples: [MetricID: MetricSample]
    public let histories: [MetricID: [Double]]
    /// Optional for backward compatibility with snapshots written before the shared
    /// state system. Consumers derive collecting/live/stale when this is absent.
    public let states: [MetricID: MetricDataState]?

    public init(
        generatedAt: Date = Date(),
        orderedMetricIDs: [MetricID],
        samples: [MetricID: MetricSample],
        histories: [MetricID: [Double]],
        states: [MetricID: MetricDataState]? = nil
    ) {
        self.generatedAt = generatedAt
        self.orderedMetricIDs = orderedMetricIDs
        self.samples = samples
        self.histories = histories
        self.states = states
    }

    public static let empty = SharedMetricSnapshot(
        generatedAt: .distantPast,
        orderedMetricIDs: [],
        samples: [:],
        histories: [:]
    )
}

/// Reads and writes the shared JSON file used by the app and its WidgetKit extension.
public struct SharedMetricSnapshotStore: Sendable {
    public static let appGroupIdentifier = "group.com.mectrics.app"
    public static let fileName = "widget-snapshot.json"

    private let fileURL: URL

    /// Creates a store inside an App Group container. Unsigned development builds fall
    /// back to Application Support so the app remains runnable before a signing team is
    /// configured; signed distribution builds use the shared container.
    public init(appGroupIdentifier: String? = Self.appGroupIdentifier) {
        if let appGroupIdentifier,
           let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
           ) {
            self.fileURL = containerURL.appendingPathComponent(Self.fileName)
        } else {
            let applicationSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!
            self.fileURL = applicationSupport
                .appendingPathComponent("Mectrics", isDirectory: true)
                .appendingPathComponent(Self.fileName)
        }
    }

    /// Creates a store at a known URL, primarily for deterministic package tests.
    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func write(_ snapshot: SharedMetricSnapshot) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        try encoder.encode(snapshot).write(to: fileURL, options: .atomic)
    }

    public func read() throws -> SharedMetricSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(
            SharedMetricSnapshot.self,
            from: Data(contentsOf: fileURL)
        )
    }
}
