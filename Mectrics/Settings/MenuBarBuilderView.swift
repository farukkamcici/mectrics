import SwiftUI
import MetricsKit

/// Visual menu bar builder (Usage-style): a live preview strip of the current menu
/// bar on top, and a gallery of component tiles below. Tiles show the module's real
/// live value/graph; click one (or drag it onto the strip) to add that module with
/// that look, click the active tile again to remove the module. No toggles, no
/// dropdowns.
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
            Text("Click a component to add it — or drag it into the menu bar above. Clicking the highlighted one removes it.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(model.availableModules, id: \.self) { id in
                        moduleRow(id)
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
            preview(id, effectiveStyle(id))
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

    private func moduleRow(_ id: MetricID) -> some View {
        HStack(spacing: 8) {
            Label(id.localizedName, systemImage: FloatingPanelView.symbol(for: id))
                .font(.callout)
                .frame(width: 96, alignment: .leading)
            ForEach(styles(for: id)) { style in
                tile(id, style)
            }
            Spacer(minLength: 0)
        }
    }

    /// Looks offered per module: sparkline-capable ones get all three, the rest
    /// just their value form.
    private func styles(for id: MetricID) -> [ModuleDisplayStyle] {
        MenuBarText.showsSparkline(id) ? ModuleDisplayStyle.allCases : [.value]
    }

    private func tile(_ id: MetricID, _ style: ModuleDisplayStyle) -> some View {
        let isActive = model.enabledModules.contains(id) && effectiveStyle(id) == style
        return VStack(spacing: 3) {
            preview(id, style)
                .frame(height: 20)
            Text(style.localizedName)
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
            if isActive {
                model.setEnabled(false, for: id)
            } else {
                model.moduleStyles[id] = style
                model.setEnabled(true, for: id)
            }
        }
        .draggable("\(id.rawValue)|\(style.rawValue)")
        .help(isActive
              ? String(localized: "builder.tile.remove", defaultValue: "Click to remove")
              : String(localized: "builder.tile.add", defaultValue: "Click to add"))
    }

    // MARK: - Live previews

    /// Miniature of how the item looks in the menu bar, driven by live data.
    @ViewBuilder
    private func preview(_ id: MetricID, _ style: ModuleDisplayStyle) -> some View {
        HStack(spacing: 4) {
            if style != .graph {
                Text(previewText(id))
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            if style != .value && MenuBarText.showsSparkline(id) {
                SparklineView(values: previewSamples(id), accent: model.accentColor)
                    .frame(width: 26, height: 13)
            }
        }
    }

    private func previewText(_ id: MetricID) -> String {
        guard let sample = model.latest[id] else { return "—" }
        // The network item is two stacked lines in the menu bar; flatten for preview.
        return MenuBarText.string(for: id, sample: sample)
            .replacingOccurrences(of: "\n", with: " ")
    }

    private func previewSamples(_ id: MetricID) -> [Double] {
        let history = model.history(id, count: 30)
        // Placeholder wave until real samples arrive.
        return history.count > 1 ? history : [0.3, 0.5, 0.35, 0.7, 0.5, 0.65, 0.45]
    }

    // MARK: - Helpers

    private func effectiveStyle(_ id: MetricID) -> ModuleDisplayStyle {
        MenuBarText.showsSparkline(id) ? model.displayStyle(for: id) : .value
    }

    /// Handles a "module|style" drag payload dropped on the strip.
    private func apply(_ payload: String) -> Bool {
        let parts = payload.split(separator: "|").map(String.init)
        guard parts.count == 2,
              let id = MetricID(rawValue: parts[0]),
              let style = ModuleDisplayStyle(rawValue: parts[1]),
              model.availableModules.contains(id)
        else { return false }
        model.moduleStyles[id] = style
        model.setEnabled(true, for: id)
        return true
    }
}
