import SwiftUI
import MetricsKit

/// Content of the floating panel: one compact live row per enabled module
/// (icon + name on the left, sparkline in the middle, current value on the right).
struct FloatingPanelView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(model.orderedEnabledModules, id: \.self) { id in
                row(id)
            }
        }
        .padding(14)
        .frame(width: 260)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.primary.opacity(0.08))
        )
    }

    private func row(_ id: MetricID) -> some View {
        HStack(spacing: 8) {
            Image(systemName: Self.symbol(for: id))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(id.localizedName)
                .font(.callout)
                .lineLimit(1)
            Spacer(minLength: 8)
            if Self.showsSparkline(id) {
                SparklineView(values: model.history(id, count: 40), accent: model.accentColor)
                    .frame(width: 52, height: 16)
            }
            Text(valueString(id))
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .frame(minWidth: 44, alignment: .trailing)
        }
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
        default:
            return MetricFormat.percent(sample.value, decimals: 0)
        }
    }

    /// Rate-like modules get a sparkline; capacity-like values stay text-only.
    private static func showsSparkline(_ id: MetricID) -> Bool {
        switch id {
        case .cpu, .memory, .network: return true
        default: return false
        }
    }

    private static func symbol(for id: MetricID) -> String {
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
