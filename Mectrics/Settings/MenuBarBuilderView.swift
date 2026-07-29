import SwiftUI
import MetricsKit

/// Visual menu bar builder (Usage-style): a live preview strip of the current menu
/// bar on top, and a gallery of component tiles below. Tiles render the module's real
/// live data in the same visual language as the menu bar; click one (or drag it onto
/// the strip) to add the module with that look or switch it. Removal lives on the
/// strip's ⓧ only.
struct MenuBarBuilderView: View {
    @Bindable var model: AppModel
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.undoManager) private var undoManager
    @State private var presentedPreset: MenuBarLayoutPreset?
    private let componentColumns = Array(
        repeating: GridItem(
            .flexible(minimum: 88, maximum: 160),
            spacing: ExperienceSpacing.small
        ),
        count: 4
    )

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.large) {
            HStack {
                Text("Current layout")
                    .font(.headline)
                Spacer()
                Menu("Presets") {
                    ForEach(MenuBarLayoutPreset.all) { preset in
                        Button(preset.name) {
                            presentedPreset = preset
                        }
                    }
                }
                Button("Reset to Recommended") {
                    apply(
                        MenuBarLayoutPreset.recommended(
                            available: Set(model.availableModules)
                        )
                    )
                }
                Toggle(
                    "Compact Health",
                    isOn: $model.compactHealthEnabled
                )
                .toggleStyle(.checkbox)
                .help(String(
                    localized: "builder.compactHealth.help",
                    defaultValue: "Show one stable health summary item in the menu bar"
                ))
                Toggle("Icons", isOn: $model.showMenuBarIcons)
                    .toggleStyle(.checkbox)
                    .help(String(
                        localized: "builder.icons.help",
                        defaultValue: "Show a module symbol before each menu bar reading"
                    ))
                Picker("Color", selection: $model.accentChoice) {
                    ForEach(AccentChoice.allCases) { choice in
                        Text(choice.localizedName).tag(choice)
                    }
                }
                .frame(width: 138)
            }
            currentStrip

            Divider()

            HStack {
                Text("Add components")
                    .font(.headline)
                Spacer()
                Text(
                    String(
                        localized: "builder.activeCount",
                        defaultValue: "\(model.orderedEnabledItems.count + (model.compactHealthEnabled ? 1 : 0)) active"
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: ExperienceSpacing.medium) {
                    ForEach(model.availableModules, id: \.self) { id in
                        moduleSection(id)
                    }
                }
                .padding(.vertical, ExperienceSpacing.tiny)
            }
        }
        .padding(ExperienceSpacing.large)
        .sheet(item: $presentedPreset) { preset in
            MenuBarPresetPreview(
                preset: preset,
                available: Set(model.availableModules),
                onCancel: { presentedPreset = nil },
                onApply: {
                    apply(preset)
                    presentedPreset = nil
                }
            )
        }
    }

    private func apply(_ preset: MenuBarLayoutPreset) {
        let prior = model.enabledComponents
        let replacement = preset.resolved(
            available: Set(model.availableModules)
        )
        guard replacement != prior else { return }
        undoManager?.registerUndo(withTarget: model) { target in
            target.enabledComponents = prior
        }
        undoManager?.setActionName(
            String(
                localized: "preset.undo.action",
                defaultValue: "Apply Menu Bar Preset"
            )
        )
        model.enabledComponents = replacement
    }

    // MARK: - Current menu bar strip

    private var currentStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: ExperienceSpacing.small) {
                if model.orderedEnabledModules.isEmpty
                    && !model.compactHealthEnabled {
                    Text("Empty — add components below")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if model.compactHealthEnabled {
                    Image(
                        systemName: model.compactHealthState.symbolName
                    )
                    .frame(width: 26)
                    .accessibilityLabel("Compact Health")
                    .accessibilityValue(
                        model.compactHealthState.localizedName
                    )
                }
                let entries = model.orderedEnabledItems
                ForEach(entries.indices, id: \.self) { i in
                    stripItem(entries[i].module, entries[i].component)
                }
            }
            .padding(.horizontal, ExperienceSpacing.medium)
            .frame(minWidth: 1, minHeight: 44, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .frame(height: 44)
        .frame(maxWidth: .infinity)
        .help(String(
            localized: "builder.reorder.help",
            defaultValue: "Hold Command and drag a menu bar item to reorder it"
        ))
        .background(
            RoundedRectangle(cornerRadius: ExperienceRadius.standard, style: .continuous)
                .fill(.secondary.opacity(0.09))
        )
        .dropDestination(for: String.self) { payloads, _ in
            guard let payload = payloads.first else { return false }
            return apply(payload)
        }
    }

    private func stripItem(_ id: MetricID, _ component: MenuBarComponent) -> some View {
        HStack(spacing: ExperienceSpacing.xSmall) {
            preview(id, component)
            Button {
                model.toggleComponent(component, for: id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help(String(localized: "builder.remove", defaultValue: "Remove from menu bar"))
            .accessibilityLabel(
                String(
                    localized: "builder.remove.accessibilityLabel",
                    defaultValue: "Remove \(component.localizedName) for \(id.localizedName)"
                )
            )
        }
        .padding(.horizontal, ExperienceSpacing.small)
        .padding(.vertical, ExperienceSpacing.xSmall)
        .background(
            RoundedRectangle(cornerRadius: ExperienceRadius.compact, style: .continuous)
                .fill(.background.opacity(0.85))
        )
    }

    // MARK: - Component gallery

    private func moduleSection(_ id: MetricID) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.small) {
            HStack(spacing: ExperienceSpacing.small) {
                Label(id.localizedName, systemImage: FloatingPanelView.symbol(for: id))
                    .font(.callout.weight(.medium))
                let state = previewState(id)
                if state != .live {
                    MetricStatusBadge(state: state)
                }
            }
            LazyVGrid(
                columns: componentColumns,
                alignment: .leading,
                spacing: ExperienceSpacing.small
            ) {
                ForEach(MenuBarComponent.available(for: id)) { component in
                    tile(id, component)
                }
            }
        }
    }

    private func tile(_ id: MetricID, _ component: MenuBarComponent) -> some View {
        let isActive = model.isComponentEnabled(component, for: id)
        return Button {
            // Multi-select: each tile toggles independently; a module can put several
            // components in the menu bar at once.
            model.toggleComponent(component, for: id)
        } label: {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: ExperienceSpacing.xSmall) {
                    preview(id, component)
                        .frame(height: 20)
                    Text(component.localizedName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 52)

                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.tint)
                        .padding(ExperienceSpacing.xSmall)
                        .accessibilityHidden(true)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: ExperienceRadius.standard, style: .continuous)
                    .fill(
                        isActive
                            ? Color.accentColor.opacity(ExperienceSurface.selectedFillOpacity)
                            : Color.secondary.opacity(ExperienceSurface.subtleFillOpacity)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: ExperienceRadius.standard, style: .continuous)
                    .strokeBorder(
                        isActive
                            ? Color.accentColor
                            : Color.primary.opacity(
                                contrast == .increased
                                    ? ExperienceSurface.increasedBorderOpacity
                                    : 0
                            ),
                        lineWidth: ExperienceChart.compactStrokeWidth
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: ExperienceRadius.standard))
        }
        .buttonStyle(.plain)
        .draggable("\(id.rawValue)|\(component.rawValue)")
        .help(isActive
              ? String(localized: "builder.tile.remove", defaultValue: "Click to remove")
              : String(localized: "builder.tile.add", defaultValue: "Click to add"))
        .accessibilityLabel(
            String(
                localized: "builder.component.accessibilityLabel",
                defaultValue: "\(id.localizedName), \(component.localizedName)"
            )
        )
        .accessibilityValue(isActive
                            ? String(localized: "builder.active", defaultValue: "In menu bar")
                            : String(localized: "builder.inactive", defaultValue: "Not in menu bar"))
    }

    // MARK: - Live previews (SwiftUI mirror of the menu bar renderer)

    @ViewBuilder
    private func preview(_ id: MetricID, _ component: MenuBarComponent) -> some View {
        let state = previewState(id)
        if showsSample(for: state), model.latest[id] != nil {
            ZStack(alignment: .topTrailing) {
                componentPreview(id, component)
                if state != .live {
                    Image(systemName: state.symbolName)
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundStyle(state.tint)
                        .accessibilityLabel(state.localizedName)
                }
            }
        } else {
            Image(systemName: state.symbolName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(state.tint)
                .accessibilityLabel(state.localizedName)
        }
    }

    @ViewBuilder
    private func componentPreview(_ id: MetricID, _ component: MenuBarComponent) -> some View {
        switch component {
        case .graph:
            SparklineView(values: previewSamples(id), accent: model.accentColor)
                .frame(width: 28, height: 14)
        case .valueGraph:
            HStack(spacing: ExperienceSpacing.xSmall) {
                previewLabel(id, component)
                SparklineView(values: previewSamples(id), accent: model.accentColor)
                    .frame(width: 26, height: 13)
            }
        case .coreBars:
            CoreBarsView(values: coreValues(id), accent: model.accentColor)
                .frame(width: 36, height: 14)
        case .ring:
            if let sample = model.latest[id] {
                ringPreview(fraction: sample.value)
            }
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
            Circle().stroke(
                .secondary.opacity(0.25),
                lineWidth: ExperienceChart.detailStrokeWidth
            )
            Circle()
                .trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(
                    model.accentColor,
                    style: StrokeStyle(
                        lineWidth: ExperienceChart.detailStrokeWidth,
                        lineCap: .round
                    )
                )
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 14, height: 14)
    }

    private func batterySymbol(_ id: MetricID) -> String {
        guard let sample = model.latest[id] else { return "battery.0percent" }
        let charging = (sample.detail["charging"] ?? 0) > 0
        if charging { return "battery.100percent.bolt" }
        let level = sample.value
        switch level {
        case ..<0.125:  return "battery.0percent"
        case ..<0.375:  return "battery.25percent"
        case ..<0.625:  return "battery.50percent"
        case ..<0.875:  return "battery.75percent"
        default:        return "battery.100percent"
        }
    }

    private func coreValues(_ id: MetricID) -> [Double] {
        guard let d = model.latest[id]?.detail else { return [] }
        let cores = Int(d["coreCount"] ?? 0)
        return (0..<cores).compactMap { d["core\($0)"] }
    }

    private func previewSamples(_ id: MetricID) -> [Double] {
        model.history(id, count: 30)
    }

    private func previewState(_ id: MetricID) -> MetricDataState {
        model.metricState(for: id, isEnabled: model.enabledModules.contains(id))
    }

    private func showsSample(for state: MetricDataState) -> Bool {
        state == .live || state == .stale || state == .error
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
        if !model.isComponentEnabled(component, for: id) {
            model.toggleComponent(component, for: id)
        }
        return true
    }
}

private struct MenuBarPresetPreview: View {
    let preset: MenuBarLayoutPreset
    let available: Set<MetricID>
    let onCancel: () -> Void
    let onApply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.medium) {
            Text(preset.name)
                .font(.title2.weight(.semibold))
            Text(preset.summary)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: ExperienceSpacing.small) {
                ForEach(Array(preset.entries.enumerated()), id: \.offset) {
                    _, entry in
                    HStack {
                        Label(
                            entry.metricID.localizedName,
                            systemImage: FloatingPanelView.symbol(
                                for: entry.metricID
                            )
                        )
                        Text(entry.component.localizedName)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if !available.contains(entry.metricID) {
                            Text("Unavailable on this Mac")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding()
            .background(
                RoundedRectangle(
                    cornerRadius: ExperienceRadius.standard
                )
                .fill(.secondary.opacity(0.08))
            )
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Apply", action: onApply)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(ExperienceSpacing.large)
        .frame(width: 480)
    }
}
