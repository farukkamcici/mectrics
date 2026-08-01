import AppKit
import Foundation
import MetricsKit
import Observation
import UniformTypeIdentifiers

enum AttentionSeverity: String, Codable, Equatable {
    case info
    case warning
    case critical
}

struct AttentionEvent: Codable, Equatable, Identifiable {
    let id: UUID
    let conditionKey: String
    let metricID: MetricID
    var state: AlertConditionState
    var severity: AttentionSeverity
    let startedAt: Date
    var activatedAt: Date?
    var endedAt: Date?
    var observedValue: Double
    let unit: MetricUnit
    let thresholdValue: Double
    let durationSeconds: Int
    var destinations: Set<AlertDestination>
    var deliveryResults: [String: String]
    var recoveryResult: String?

    var isResolved: Bool { endedAt != nil }
}

private struct AttentionLogArchive: Codable {
    let schemaVersion: Int
    var events: [AttentionEvent]
}

/// A bounded, local record of meaningful condition transitions. It stores structured
/// allowlisted values only—never hostnames, usernames, paths, processes, addresses, or
/// hardware identifiers.
@Observable
@MainActor
final class AttentionLogStore {
    private(set) var events: [AttentionEvent]

    private let fileURL: URL
    private let now: () -> Date
    private let retention: TimeInterval
    private let capacity: Int

    init(
        fileURL: URL? = nil,
        retention: TimeInterval = 30 * 24 * 60 * 60,
        capacity: Int = 500,
        now: @escaping () -> Date = Date.init
    ) {
        self.fileURL = fileURL ?? Self.defaultFileURL
        self.retention = retention
        self.capacity = capacity
        self.now = now
        self.events = Self.load(from: self.fileURL)
        prune()
    }

    var unresolvedEvents: [AttentionEvent] {
        events
            .filter { !$0.isResolved }
            .sorted { $0.startedAt > $1.startedAt }
    }

    var resolvedEvents: [AttentionEvent] {
        events
            .filter(\.isResolved)
            .sorted { $0.startedAt > $1.startedAt }
    }

    func apply(_ update: AlertConditionUpdate, at date: Date? = nil) {
        let eventDate = date ?? now()
        let conditionKey = update.conditionKey
        let existingIndex = events.firstIndex {
            $0.conditionKey == conditionKey && !$0.isResolved
        }

        switch update.transition {
        case .pending, .activated:
            guard update.destinations.contains(.attentionLog)
                    || existingIndex != nil else { return }
            if let existingIndex {
                events[existingIndex].state = update.state
                events[existingIndex].severity = Self.severity(for: update)
                events[existingIndex].observedValue = update.measuredValue
                events[existingIndex].destinations = update.destinations
                if update.transition == .activated {
                    events[existingIndex].activatedAt = eventDate
                    recordRequestedDeliveries(at: existingIndex)
                }
            } else {
                var event = AttentionEvent(
                    id: UUID(),
                    conditionKey: conditionKey,
                    metricID: update.metricID,
                    state: update.state,
                    severity: Self.severity(for: update),
                    startedAt: update.startedAt ?? eventDate,
                    activatedAt: update.transition == .activated ? eventDate : nil,
                    endedAt: nil,
                    observedValue: update.measuredValue,
                    unit: update.unit,
                    thresholdValue: update.thresholdValue,
                    durationSeconds: update.durationSeconds,
                    destinations: update.destinations,
                    deliveryResults: [:],
                    recoveryResult: nil
                )
                if update.transition == .activated {
                    event.deliveryResults = Self.requestedDeliveries(
                        update.destinations
                    )
                }
                events.append(event)
            }
        case .recovered:
            guard let existingIndex else { return }
            events[existingIndex].state = .normal
            events[existingIndex].endedAt = eventDate
            events[existingIndex].observedValue = update.measuredValue
            events[existingIndex].recoveryResult = "recovered"
        }

        prune()
        persist()
    }

    func clear() {
        events.removeAll()
        persist()
    }

    func exportText(generatedAt: Date? = nil) -> String {
        let generatedAt = generatedAt ?? now()
        var lines = [
            String(
                localized: "attention.export.title",
                defaultValue: "Mectrics Attention Log"
            ),
            "Schema: mectrics.attention-log.v1",
            "Generated: \(Self.iso8601.string(from: generatedAt))",
            ""
        ]

        if events.isEmpty {
            lines.append(String(
                localized: "attention.export.empty",
                defaultValue: "No attention events."
            ))
            return lines.joined(separator: "\n") + "\n"
        }

        for event in events.sorted(by: { $0.startedAt > $1.startedAt }) {
            lines.append("[\(event.id.uuidString)]")
            lines.append("Metric: \(event.metricID.rawValue)")
            lines.append("Severity: \(event.severity.rawValue)")
            lines.append("State: \(event.state.rawValue)")
            lines.append("Started: \(Self.iso8601.string(from: event.startedAt))")
            if let activatedAt = event.activatedAt {
                lines.append("Activated: \(Self.iso8601.string(from: activatedAt))")
            }
            if let endedAt = event.endedAt {
                lines.append("Ended: \(Self.iso8601.string(from: endedAt))")
            }
            lines.append(
                "Observed: \(Self.number(event.observedValue)) \(event.unit.rawValue)"
            )
            lines.append("Threshold: \(Self.number(event.thresholdValue))")
            lines.append("Sustained seconds: \(event.durationSeconds)")
            lines.append(
                "Destinations: \(event.destinations.map(\.rawValue).sorted().joined(separator: ", "))"
            )
            if !event.deliveryResults.isEmpty {
                let results = event.deliveryResults
                    .map { "\($0.key)=\($0.value)" }
                    .sorted()
                    .joined(separator: ", ")
                lines.append("Delivery: \(results)")
            }
            if let recoveryResult = event.recoveryResult {
                lines.append("Recovery: \(recoveryResult)")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    func saveExport(_ text: String) {
        let panel = NSSavePanel()
        panel.title = String(
            localized: "attention.export.saveTitle",
            defaultValue: "Save Attention Log"
        )
        panel.nameFieldStringValue = "mectrics-attention-log.txt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? Data(text.utf8).write(to: url, options: .atomic)
    }

    private func recordRequestedDeliveries(at index: Int) {
        events[index].deliveryResults = Self.requestedDeliveries(
            events[index].destinations
        )
    }

    private static func requestedDeliveries(
        _ destinations: Set<AlertDestination>
    ) -> [String: String] {
        Dictionary(uniqueKeysWithValues: destinations.map {
            ($0.rawValue, "requested")
        })
    }

    private func prune() {
        let cutoff = now().addingTimeInterval(-retention)
        events.removeAll { event in
            (event.endedAt ?? event.startedAt) < cutoff
        }
        events.sort {
            if $0.isResolved != $1.isResolved { return !$0.isResolved }
            return $0.startedAt > $1.startedAt
        }
        if events.count > capacity {
            events.removeLast(events.count - capacity)
        }
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let archive = AttentionLogArchive(schemaVersion: 1, events: events)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .millisecondsSince1970
            try encoder.encode(archive).write(to: fileURL, options: .atomic)
        } catch {
            // Logging must never destabilize the metrics hot path.
        }
    }

    private static func load(from url: URL) -> [AttentionEvent] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return (try? decoder.decode(AttentionLogArchive.self, from: data).events) ?? []
    }

    private static let defaultFileURL: URL = {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        .appendingPathComponent("Mectrics", isDirectory: true)
        .appendingPathComponent("attention-log.json")
    }()

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static func number(_ value: Double) -> String {
        String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private static func severity(
        for update: AlertConditionUpdate
    ) -> AttentionSeverity {
        guard update.state == .active else { return .info }
        return AlertConditionSeverity.resolve(update)
    }
}
