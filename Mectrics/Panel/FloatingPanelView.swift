import SwiftUI
import MetricsKit

/// Content of the floating panel in one of two fixed layouts (Settings > General):
/// - horizontal: a single-row strip — icon + value (+ mini sparkline) per module,
///   ideal parked along the top of the screen;
/// - vertical: a card with one module per row — icon + name + sparkline + value.
/// The panel window sizes itself to this content; there is no manual resizing.
struct FloatingPanelView: View {
    @Bindable var model: AppModel

    var body: some View {
        Group {
            switch model.panelLayout {
            case .horizontal: horizontalStrip
            case .vertical:   verticalCard
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.primary.opacity(0.08))
        )
    }

    // MARK: - Layouts

    private var horizontalStrip: some View {
        HStack(spacing: 14) {
            ForEach(model.orderedEnabledModules, id: \.self) { id in
                HStack(spacing: 6) {
                    icon(id)
                    valueText(id, size: 11)
                    if Self.showsSparkline(id) {
                        SparklineView(values: model.history(id, count: 30), accent: model.accentColor)
                            .frame(width: 26, height: 12)
                    }
                }
                .help(id.localizedName)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var verticalCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(model.orderedEnabledModules, id: \.self) { id in
                HStack(spacing: 7) {
                    icon(id)
                    Text(id.localizedName)
                        .font(.callout)
                        .lineLimit(1)
                    Spacer(minLength: 10)
                    if Self.showsSparkline(id) {
                        SparklineView(values: model.history(id, count: 40), accent: model.accentColor)
                            .frame(width: 44, height: 14)
                    }
                    valueText(id, size: 12)
                        .frame(minWidth: 46, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .frame(width: 240)
    }

    // MARK: - Pieces

    private func icon(_ id: MetricID) -> some View {
        Image(systemName: Self.symbol(for: id))
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: 14)
    }

    private func valueText(_ id: MetricID, size: CGFloat) -> some View {
        Text(valueString(id))
            .font(.system(size: size, weight: .semibold))
            .monospacedDigit()
            .lineLimit(1)
    }

    // MARK: - Formatting

    private func valueString(_ id: MetricID) -> String {
        guard let sample = model.latest[id] else { return "—" }
        switch id {
        case .cpu, .memory, .disk:
            return MetricFormat.percent(sample.value, decimals: 0)
        case .battery, .bluetooth:
            return "\(Int((sample.value * 100).rounded()))%"
        case .network:
            let down = sample.detail["down"] ?? 0
            let up = sample.detail["up"] ?? 0
            return "↓\(MetricFormat.menuRate(down)) ↑\(MetricFormat.menuRate(up))"
        case .sensors:
            return "\(Int(sample.value.rounded()))°"
        case .fans:
            return MetricFormat.menuRate(sample.detail["maxRpm"] ?? 0)
        default:
            return MetricFormat.percent(sample.value, decimals: 0)
        }
    }

    /// Rate-like modules get a sparkline; capacity-like values stay text-only.
    private static func showsSparkline(_ id: MetricID) -> Bool {
        switch id {
        case .cpu, .memory, .network, .gpu: return true
        default: return false
        }
    }

    /// SF Symbol per module — shared with the settings menu bar builder.
    static func symbol(for id: MetricID) -> String {
        switch id {
        case .cpu:       return "cpu"
        case .memory:    return "memorychip"
        case .battery:   return "battery.100percent"
        case .network:   return "arrow.up.arrow.down"
        case .disk:      return "internaldrive"
        case .bluetooth: return "wave.3.right"
        case .gpu:       return "rectangle.on.rectangle"
        case .sensors:   return "thermometer.medium"
        case .fans:      return "fan"
        case .clock:     return "clock"
        }
    }
}
