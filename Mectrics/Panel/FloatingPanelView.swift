import SwiftUI
import MetricsKit

/// Content of the floating panel: one compact chip per enabled module (icon + live
/// value + mini sparkline where it makes sense), flowing into as many columns as the
/// window width allows. Stretched wide the panel becomes a single thin strip; narrow,
/// the chips wrap into rows. The window itself is user-resizable from any edge.
struct FloatingPanelView: View {
    @Bindable var model: AppModel
    /// Reports the content's natural height so the window can follow it as chips wrap.
    var onHeightChange: (CGFloat) -> Void = { _ in }

    private let columns = [
        GridItem(.adaptive(minimum: 108, maximum: 220), spacing: 6, alignment: .leading)
    ]

    var body: some View {
        VStack(spacing: 0) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                ForEach(model.orderedEnabledModules, id: \.self) { id in
                    chip(id)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: PanelHeightKey.self, value: geo.size.height)
                }
            )
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.primary.opacity(0.08))
        )
        // Resize affordance: a horizontal-arrows cursor on the left/right edges.
        .overlay(alignment: .leading) { resizeHoverZone }
        .overlay(alignment: .trailing) { resizeHoverZone }
        .onPreferenceChange(PanelHeightKey.self) { onHeightChange($0) }
    }

    private var resizeHoverZone: some View {
        Color.clear
            .frame(width: 7)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
    }

    private func chip(_ id: MetricID) -> some View {
        HStack(spacing: 5) {
            Image(systemName: Self.symbol(for: id))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 13)
            Text(valueString(id))
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
            if Self.showsSparkline(id) {
                SparklineView(values: model.history(id, count: 30), accent: model.accentColor)
                    .frame(width: 26, height: 11)
            }
        }
        .help(id.localizedName)
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

/// Preference carrying the chip grid's natural height up to the window controller.
private struct PanelHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 44
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
