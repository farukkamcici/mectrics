import SwiftUI
import MetricsKit

/// Visual menu bar builder (Usage-style): a live preview strip of the current menu
/// bar on top, and a gallery of component tiles below. Tiles render the module's real
/// live data in the same visual language as the menu bar; click one (or drag it onto
/// the strip) to add the module with that look or switch it. Removal lives on the
/// strip's ⓧ only.
struct MenuBarBuilderView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Menu bar")
                .font(.headline)
            currentStrip
            Text("Reorder items directly in the menu bar by holding ⌘ and dragging them.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Divider()

            Text("Components")
                .font(.headline)
            Text("Click a component (or drag it into the menu bar above) to add it or switch its look. Remove items with the ⓧ in the menu bar preview.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(model.availableModules, id: \.self) { id in
                        moduleSection(id)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(14)
    }

    // MARK: - Current menu bar strip

    private var currentStrip: some View {
        HStack(spacing: 6) {
            if model.orderedEnabledModules.isEmpty {
                Text("Empty — add components below")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(model.orderedEnabledModules, id: \.self) { id in
                stripItem(id)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(.secondary.opacity(0.09))
        )
        .dropDestination(for: String.self) { payloads, _ in
            guard let payload = payloads.first else { return false }
            return apply(payload)
        }
    }

    private func stripItem(_ id: MetricID) -> some View {
        HStack(spacing: 5) {
            preview(id, model.component(for: id))
            Button {
                model.setEnabled(false, for: id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help(String(localized: "builder.remove", defaultValue: "Remove from menu bar"))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.background.opacity(0.85))
                .shadow(color: .black.opacity(0.12), radius: 1, y: 0.5)
        )
    }

    // MARK: - Component gallery

    private func moduleSection(_ id: MetricID) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(id.localizedName, systemImage: FloatingPanelView.symbol(for: id))
                .font(.callout.weight(.medium))
            HStack(spacing: 8) {
                ForEach(MenuBarComponent.available(for: id)) { component in
                    tile(id, component)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func tile(_ id: MetricID, _ component: MenuBarComponent) -> some View {
        let isActive = model.enabledModules.contains(id) && model.component(for: id) == component
        return VStack(spacing: 3) {
            preview(id, component)
                .frame(height: 20)
            Text(component.localizedName)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: 92, height: 48)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isActive ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isActive ? Color.accentColor : .clear, lineWidth: 1.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture {
            // Tap only ever adds or switches the look — removal lives on the strip's ⓧ,
            // so exploring tiles can never silently drop items from the menu bar.
            guard !isActive else { return }
            model.moduleComponents[id] = component
            model.setEnabled(true, for: id)
        }
        .draggable("\(id.rawValue)|\(component.rawValue)")
        .help(isActive
              ? String(localized: "builder.tile.active", defaultValue: "In the menu bar")
              : String(localized: "builder.tile.add", defaultValue: "Click to add"))
    }

    // MARK: - Live previews (SwiftUI mirror of the menu bar renderer)

    @ViewBuilder
    private func preview(_ id: MetricID, _ component: MenuBarComponent) -> some View {
        switch component {
        case .graph:
            SparklineView(values: previewSamples(id), accent: model.accentColor)
                .frame(width: 28, height: 14)
        case .valueGraph:
            HStack(spacing: 4) {
                previewLabel(id, component)
                SparklineView(values: previewSamples(id), accent: model.accentColor)
                    .frame(width: 26, height: 13)
            }
        case .coreBars:
            CoreBarsView(values: coreValues(id), accent: model.accentColor)
                .frame(width: 36, height: 14)
        case .ring:
            ringPreview(fraction: model.latest[id]?.value ?? 0)
        case .batteryIcon:
            Image(systemName: batterySymbol(id))
                .font(.system(size: 13))
        default:
            previewLabel(id, component)
        }
    }

    private func previewLabel(_ id: MetricID, _ component: MenuBarComponent) -> some View {
        Text(previewText(id, component))
            .font(.system(size: 11, weight: .medium))
            .monospacedDigit()
            .lineLimit(1)
    }

    private func previewText(_ id: MetricID, _ component: MenuBarComponent) -> String {
        guard let sample = model.latest[id] else { return "—" }
        if case .text(let text) = MenuBarText.visual(for: id, component: component, sample: sample) {
            return text.replacingOccurrences(of: "\n", with: " ")
        }
        return MenuBarText.string(for: id, sample: sample)
            .replacingOccurrences(of: "\n", with: " ")
    }

    private func ringPreview(fraction: Double) -> some View {
        ZStack {
            Circle().stroke(.secondary.opacity(0.25), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(model.accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 14, height: 14)
    }

    private func batterySymbol(_ id: MetricID) -> String {
        let sample = model.latest[id]
        let charging = (sample?.detail["charging"] ?? 0) > 0
        if charging { return "battery.100percent.bolt" }
        let level = sample?.value ?? 1
        switch level {
        case ..<0.125:  return "battery.0percent"
        case ..<0.375:  return "battery.25percent"
        case ..<0.625:  return "battery.50percent"
        case ..<0.875:  return "battery.75percent"
        default:        return "battery.100percent"
        }
    }

    private func coreValues(_ id: MetricID) -> [Double] {
        guard let d = model.latest[id]?.detail else { return [0.3, 0.6, 0.4, 0.7] }
        let cores = Int(d["coreCount"] ?? 0)
        let values = (0..<cores).compactMap { d["core\($0)"] }
        return values.isEmpty ? [0.3, 0.6, 0.4, 0.7] : values
    }

    private func previewSamples(_ id: MetricID) -> [Double] {
        let history = model.history(id, count: 30)
        // Placeholder wave until real samples arrive.
        return history.count > 1 ? history : [0.3, 0.5, 0.35, 0.7, 0.5, 0.65, 0.45]
    }

    // MARK: - Helpers

    /// Handles a "module|component" drag payload dropped on the strip.
    private func apply(_ payload: String) -> Bool {
        let parts = payload.split(separator: "|").map(String.init)
        guard parts.count == 2,
              let id = MetricID(rawValue: parts[0]),
              let component = MenuBarComponent(rawValue: parts[1]),
              model.availableModules.contains(id),
              MenuBarComponent.available(for: id).contains(component)
        else { return false }
        model.moduleComponents[id] = component
        model.setEnabled(true, for: id)
        return true
    }
}
