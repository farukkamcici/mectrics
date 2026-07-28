import SwiftUI
import WidgetKit
import MetricsKit

private struct MetricsEntry: TimelineEntry {
    let date: Date
    let snapshot: SharedMetricSnapshot
}

private struct MetricsTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> MetricsEntry {
        MetricsEntry(date: Date(), snapshot: Self.previewSnapshot)
    }

    func getSnapshot(in context: Context, completion: @escaping (MetricsEntry) -> Void) {
        completion(MetricsEntry(
            date: Date(),
            snapshot: context.isPreview ? Self.previewSnapshot : loadSnapshot()
        ))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MetricsEntry>) -> Void) {
        let now = Date()
        let entry = MetricsEntry(date: now, snapshot: loadSnapshot())
        completion(Timeline(
            entries: [entry],
            policy: .after(now.addingTimeInterval(15 * 60))
        ))
    }

    private func loadSnapshot() -> SharedMetricSnapshot {
#if DEBUG
        let store = SharedMetricSnapshotStore(appGroupIdentifier: nil)
#else
        let store = SharedMetricSnapshotStore()
#endif
        return (try? store.read()) ?? .empty
    }

    private static let previewSnapshot = SharedMetricSnapshot(
        orderedMetricIDs: [.cpu, .memory, .battery, .network, .gpu],
        samples: [
            .cpu: MetricSample(value: 0.34),
            .memory: MetricSample(value: 0.68),
            .battery: MetricSample(value: 0.82),
            .network: MetricSample(
                value: 0,
                unit: .bytesPerSecond,
                detail: ["down": 2_400_000, "up": 180_000]
            ),
            .gpu: MetricSample(value: 0.21)
        ],
        histories: [
            .cpu: [0.18, 0.25, 0.22, 0.48, 0.34],
            .memory: [0.61, 0.63, 0.65, 0.66, 0.68],
            .gpu: [0.08, 0.15, 0.12, 0.32, 0.21]
        ]
    )
}

struct MectricsOverviewWidget: Widget {
    let kind = "MectricsOverviewWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MetricsTimelineProvider()) { entry in
            MetricsWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Mectrics Overview")
        .description("See your Mac's latest system metrics at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct MectricsWidgetBundle: WidgetBundle {
    var body: some Widget {
        MectricsOverviewWidget()
    }
}

private struct MetricsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MetricsEntry

    private var visibleMetricIDs: [MetricID] {
        let limit = switch family {
        case .systemSmall: 3
        case .systemMedium: 5
        default: 8
        }
        return Array(entry.snapshot.orderedMetricIDs.prefix(limit))
    }

    var body: some View {
        if visibleMetricIDs.isEmpty {
            ContentUnavailableView {
                Label("Waiting for Mectrics", systemImage: "ellipsis")
            } description: {
                Text("Launch the app once to show live readings.")
            }
        } else {
            VStack(alignment: .leading, spacing: family == .systemSmall ? 8 : 10) {
                header
                ForEach(visibleMetricIDs, id: \.self) { id in
                    metricRow(id)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var header: some View {
        HStack {
            Label("Mectrics", systemImage: "waveform.path.ecg")
                .font(.headline)
            Spacer()
            Text(entry.snapshot.generatedAt, style: .time)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func metricRow(_ id: MetricID) -> some View {
        let state = entry.snapshot.states?[id] ?? MetricDataState.resolve(
                isAvailable: true,
                isEnabled: true,
                sample: entry.snapshot.samples[id],
                now: entry.date,
                staleAfter: 30 * 60
            )
        return HStack(spacing: 7) {
            Image(systemName: symbol(for: id))
                .foregroundStyle(.secondary)
                .frame(width: 15)
            Text(localizedName(for: id))
                .font(.caption)
                .lineLimit(1)
            if family != .systemSmall,
               let values = entry.snapshot.histories[id],
               values.count > 1 {
                SnapshotSparkline(values: values)
                    .stroke(.tint, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .frame(height: 14)
            }
            Spacer(minLength: 4)
            if state != .live {
                Image(systemName: stateSymbol(for: state))
                    .font(.caption2)
                    .foregroundStyle(state == .stale ? .orange : .secondary)
                    .accessibilityLabel(stateName(for: state))
            }
            Text(value(for: id))
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(localizedName(for: id))
        .accessibilityValue(
            String(
                localized: "metric.accessibility.valueAndState",
                defaultValue: "\(value(for: id)), \(stateName(for: state))"
            )
        )
    }

    private func value(for id: MetricID) -> String {
        guard let sample = entry.snapshot.samples[id] else { return "—" }
        switch id {
        case .cpu, .memory, .battery, .disk, .gpu, .bluetooth:
            return MetricFormat.percent(sample.value)
        case .network:
            return "↓\(MetricFormat.menuRate(sample.detail["down"] ?? 0))"
        case .sensors:
            return "\(Int(sample.value.rounded()))°"
        case .fans:
            return "\(Int((sample.detail["maxRpm"] ?? 0).rounded())) RPM"
        case .clock:
            return "—"
        }
    }

    private func symbol(for id: MetricID) -> String {
        switch id {
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        case .battery: return "battery.100percent"
        case .network: return "arrow.up.arrow.down"
        case .disk: return "internaldrive"
        case .gpu: return "rectangle.on.rectangle"
        case .sensors: return "thermometer.medium"
        case .fans: return "fan"
        case .bluetooth: return "wave.3.right"
        case .clock: return "clock"
        }
    }

    private func localizedName(for id: MetricID) -> String {
        switch id {
        case .cpu: return String(localized: "module.cpu", defaultValue: "CPU")
        case .memory: return String(localized: "module.memory", defaultValue: "Memory")
        case .battery: return String(localized: "module.battery", defaultValue: "Battery")
        case .network: return String(localized: "module.network", defaultValue: "Network")
        case .disk: return String(localized: "module.disk", defaultValue: "Disk")
        case .gpu: return String(localized: "module.gpu", defaultValue: "GPU")
        case .sensors: return String(localized: "module.sensors", defaultValue: "Sensors")
        case .fans: return String(localized: "module.fans", defaultValue: "Fans")
        case .bluetooth: return String(localized: "module.bluetooth", defaultValue: "Bluetooth")
        case .clock: return String(localized: "module.clock", defaultValue: "Clock")
        }
    }

    private func stateName(for state: MetricDataState) -> String {
        switch state {
        case .collecting:
            return String(localized: "state.collecting", defaultValue: "Collecting")
        case .live:
            return String(localized: "state.live", defaultValue: "Live")
        case .unavailable:
            return String(localized: "state.unavailable", defaultValue: "Unavailable")
        case .disabled:
            return String(localized: "state.disabled", defaultValue: "Disabled")
        case .permissionRequired:
            return String(localized: "state.permissionRequired", defaultValue: "Permission required")
        case .stale:
            return String(localized: "state.stale", defaultValue: "Last known")
        case .error:
            return String(localized: "state.error", defaultValue: "Needs attention")
        }
    }

    private func stateSymbol(for state: MetricDataState) -> String {
        switch state {
        case .collecting: return "ellipsis"
        case .live: return "checkmark.circle.fill"
        case .unavailable: return "slash.circle"
        case .disabled: return "minus.circle"
        case .permissionRequired: return "lock.trianglebadge.exclamationmark"
        case .stale: return "clock.badge.exclamationmark"
        case .error: return "exclamationmark.triangle.fill"
        }
    }
}

private struct SnapshotSparkline: Shape {
    let values: [Double]

    func path(in rect: CGRect) -> Path {
        guard values.count > 1 else { return Path() }
        let minimum = values.min() ?? 0
        let maximum = values.max() ?? 1
        let range = max(maximum - minimum, 0.0001)
        var path = Path()
        for (index, value) in values.enumerated() {
            let x = rect.minX + CGFloat(index) / CGFloat(values.count - 1) * rect.width
            let normalized = (value - minimum) / range
            let y = rect.maxY - CGFloat(normalized) * rect.height
            let point = CGPoint(x: x, y: y)
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path
    }
}
