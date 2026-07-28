import SwiftUI
import MetricsKit

/// Content of the floating panel in one of two fixed layouts (Settings > General):
/// - horizontal: a single-row strip — icon + value (+ mini sparkline) per module,
///   ideal parked along the top of the screen;
/// - vertical: a card with one module per row — icon + name + sparkline + value.
/// The panel window sizes itself to this content; there is no manual resizing.
struct FloatingPanelView: View {
    @Bindable var model: AppModel
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Group {
            switch model.panelLayout {
            case .horizontal: horizontalStrip
            case .vertical:   verticalCard
            }
        }
        .background {
            let shape = RoundedRectangle(
                cornerRadius: ExperienceRadius.panel,
                style: .continuous
            )
            if reduceTransparency {
                shape.fill(Color(nsColor: .windowBackgroundColor))
            } else {
                shape.fill(ExperienceSurface.floatingMaterial)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: ExperienceRadius.panel, style: .continuous)
                .strokeBorder(
                    .primary.opacity(
                        contrast == .increased
                            ? ExperienceSurface.increasedBorderOpacity
                            : ExperienceSurface.standardBorderOpacity
                    )
                )
        )
    }

    // MARK: - Layouts

    private var horizontalStrip: some View {
        HStack(spacing: ExperienceSpacing.medium) {
            ForEach(model.orderedEnabledModules, id: \.self) { id in
                HStack(spacing: ExperienceSpacing.small) {
                    icon(id)
                    // Window size is measured once per layout change, so values get a
                    // stable min width to avoid clipping as digits grow.
                    valueText(id, size: 11)
                        .frame(
                            minWidth: id == .network ? 78 : (id == .fans ? 64 : 32),
                            alignment: .leading
                        )
                    if Self.showsSparkline(id) {
                        SparklineView(values: model.history(id, count: 30), accent: model.accentColor)
                            .frame(width: 26, height: 12)
                    }
                    stateIndicator(id)
                }
                .help(id.localizedName)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, ExperienceSpacing.medium)
        .padding(.vertical, ExperienceSpacing.small)
    }

    private var verticalCard: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.small) {
            ForEach(model.orderedEnabledModules, id: \.self) { id in
                HStack(spacing: ExperienceSpacing.small) {
                    icon(id)
                    Text(id.localizedName)
                        .font(.callout)
                        .lineLimit(1)
                    stateIndicator(id)
                    Spacer(minLength: 10)
                    if Self.showsSparkline(id) {
                        SparklineView(values: model.history(id, count: 40), accent: model.accentColor)
                            .frame(width: 44, height: 14)
                    }
                    valueText(id, size: 12)
                        .frame(minWidth: 46, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, ExperienceSpacing.medium)
        .padding(.vertical, ExperienceSpacing.medium)
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
            .accessibilityLabel(id.localizedName)
            .accessibilityValue(valueString(id))
            .accessibilityHint(model.metricState(for: id, isEnabled: true).localizedName)
    }

    @ViewBuilder
    private func stateIndicator(_ id: MetricID) -> some View {
        let state = model.metricState(for: id, isEnabled: true)
        if state != .live {
            Image(systemName: state.symbolName)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(state.tint)
                .help(state.reason)
                .accessibilityLabel(state.localizedName)
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
        case .sensors:
            return "\(Int(sample.value.rounded()))°"
        case .fans:
            return "\(MetricFormat.menuRate(sample.detail["maxRpm"] ?? 0)) RPM"
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
