import SwiftUI
import MetricsKit

/// Menu bar tab of the settings window.
///
/// The pane reads top-down: a read-only preview of the menu bar as it will look, one
/// row per module for choosing what that module shows, then appearance. A module owns
/// at most one item, so this is a list of choices rather than a grid of toggles, and
/// the whole pane fits without scrolling.
struct MenuBarBuilderView: View {
    @Bindable var model: AppModel
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        Form {
            Section {
                previewStrip
            } header: {
                Text("Preview")
            } footer: {
                Text("Hold Command and drag an item in the menu bar to reorder it.")
            }

            Section {
                ForEach(model.availableModules, id: \.self) { id in
                    moduleRow(id)
                }
            } header: {
                HStack {
                    Text("Modules")
                    Spacer()
                    presetsMenu
                }
            }

            Section {
                Toggle("Show module icons", isOn: $model.showMenuBarIcons)
                Picker("Chart color", selection: $model.accentChoice) {
                    ForEach(AccentChoice.allCases) { choice in
                        Text(choice.localizedName).tag(choice)
                    }
                }
            } header: {
                Text("Appearance")
            }

            Section {
                Toggle(
                    "Show Compact Health item",
                    isOn: $model.compactHealthEnabled
                )
            } footer: {
                Text("One extra menu bar item that stays quiet until an alert sent to it becomes active.")
            }
        }
        .formStyle(.grouped)
        // Preview tiles are only honest if every module is being sampled, including
        // the ones the user has not added yet.
        .onAppear { model.beginBuilderPreview() }
        .onDisappear { model.endBuilderPreview() }
    }

    // MARK: - Presets

    private var presetsMenu: some View {
        Menu("Presets") {
            ForEach(MenuBarLayoutPreset.all) { preset in
                // The count is what a preset costs in menu bar space, which is the
                // scarce resource here, so it is part of the choice.
                let count = preset.itemCount(
                    available: Set(model.availableModules)
                )
                Button(
                    String(
                        localized: "preset.menuTitle",
                        defaultValue: "\(preset.name) — \(count) items"
                    )
                ) {
                    apply(preset)
                }
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
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

    // MARK: - Preview strip

    private var previewStrip: some View {
        HStack(spacing: ExperienceSpacing.medium) {
            if model.compactHealthEnabled {
                Image(systemName: model.compactHealthState.symbolName)
                    .accessibilityLabel("Compact Health")
                    .accessibilityValue(model.compactHealthState.localizedName)
            }
            ForEach(model.orderedEnabledItems.indices, id: \.self) { index in
                let entry = model.orderedEnabledItems[index]
                previewItem(entry.module, entry.component)
            }
            if model.orderedEnabledItems.isEmpty && !model.compactHealthEnabled {
                Text("Nothing in the menu bar yet — pick a look for a module below.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, ExperienceSpacing.medium)
        .frame(minHeight: 34)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(
                cornerRadius: ExperienceRadius.compact,
                style: .continuous
            )
            .fill(.secondary.opacity(0.09))
        )
    }

    private func previewItem(
        _ id: MetricID,
        _ component: MenuBarComponent
    ) -> some View {
        HStack(spacing: ExperienceSpacing.xSmall) {
            if model.showMenuBarIcons && !component.drawsModuleGlyph {
                Image(systemName: MetricSymbol.name(for: id))
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(model.accentColor)
            }
            preview(id, component)
        }
        .help(id.localizedName)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            String(
                localized: "builder.component.accessibilityLabel",
                defaultValue: "\(id.localizedName), \(component.localizedName)"
            )
        )
    }

    // MARK: - Module rows

    private func moduleRow(_ id: MetricID) -> some View {
        let state = previewState(id)
        return LabeledContent {
            HStack(spacing: ExperienceSpacing.small) {
                Spacer(minLength: 0)
                ForEach(model.availableComponents(for: id)) { component in
                    componentChip(id, component)
                }
            }
        } label: {
            HStack(spacing: ExperienceSpacing.small) {
                Label(
                    id.localizedName,
                    systemImage: MetricSymbol.name(for: id)
                )
                // Only genuine problems earn a badge. "Not in the menu bar" is
                // already visible in the chips themselves.
                if Self.isProblem(state) {
                    MetricStatusBadge(state: state)
                        .help(state.reason)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// One look for one module. Chips are independent: a module can put several items
    /// in the menu bar at once, and each chip shows the real thing it will draw.
    private func componentChip(
        _ id: MetricID,
        _ component: MenuBarComponent
    ) -> some View {
        let isActive = model.isComponentEnabled(component, for: id)
        return Button {
            model.toggleComponent(component, for: id)
        } label: {
            VStack(spacing: 3) {
                preview(id, component)
                    .frame(height: 16)
                Text(component.localizedName)
                    .font(.caption2)
                    .foregroundStyle(isActive ? .primary : .secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, ExperienceSpacing.small)
            .padding(.vertical, ExperienceSpacing.xSmall)
            .frame(minWidth: 62)
            .background(
                RoundedRectangle(
                    cornerRadius: ExperienceRadius.compact,
                    style: .continuous
                )
                .fill(
                    isActive
                        ? Color.accentColor.opacity(
                            ExperienceSurface.selectedFillOpacity
                        )
                        : Color.secondary.opacity(
                            ExperienceSurface.subtleFillOpacity
                        )
                )
            )
            .overlay(
                RoundedRectangle(
                    cornerRadius: ExperienceRadius.compact,
                    style: .continuous
                )
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
            .contentShape(
                RoundedRectangle(cornerRadius: ExperienceRadius.compact)
            )
        }
        .buttonStyle(.plain)
        .help(isActive
              ? String(localized: "builder.chip.remove", defaultValue: "Click to remove from the menu bar")
              : String(localized: "builder.chip.add", defaultValue: "Click to add to the menu bar"))
        .accessibilityLabel(
            String(
                localized: "builder.component.accessibilityLabel",
                defaultValue: "\(id.localizedName), \(component.localizedName)"
            )
        )
        .accessibilityValue(isActive
                            ? String(localized: "builder.active", defaultValue: "In menu bar")
                            : String(localized: "builder.inactive", defaultValue: "Not in menu bar"))
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private static func isProblem(_ state: MetricDataState) -> Bool {
        switch state {
        case .live, .disabled, .collecting:
            return false
        case .stale, .error, .permissionRequired, .unavailable:
            return true
        }
    }

    // MARK: - Live previews (SwiftUI mirror of the menu bar renderer)

    @ViewBuilder
    private func preview(_ id: MetricID, _ component: MenuBarComponent) -> some View {
        if model.latest[id] != nil {
            componentPreview(id, component)
        } else {
            let state = previewState(id)
            Image(systemName: state.symbolName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(state.tint)
                .accessibilityLabel(state.localizedName)
        }
    }

    @ViewBuilder
    private func componentPreview(_ id: MetricID, _ component: MenuBarComponent) -> some View {
        switch component {
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
        case .batteryIconValue:
            labelledBatteryPreview(id)
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

    /// SwiftUI mirror of the menu bar's labelled battery: body, fill, charge inside.
    private func labelledBatteryPreview(_ id: MetricID) -> some View {
        let sample = model.latest[id]
        let level = min(max(sample?.value ?? 0, 0), 1)
        let charging = (sample?.detail["charging"] ?? 0) > 0
        return HStack(spacing: 1) {
            ZStack {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .strokeBorder(.primary.opacity(0.55), lineWidth: 1)
                GeometryReader { proxy in
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(
                            level <= 0.2 && !charging
                                ? Color.red
                                : Color.primary.opacity(0.85)
                        )
                        .frame(width: proxy.size.width * level)
                }
                .padding(1.5)
                Text("\(Int((level * 100).rounded()))")
                    .font(.system(size: 7.5, weight: .bold).monospacedDigit())
                    .blendMode(.difference)
            }
            .frame(width: 24, height: 11)
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(.primary.opacity(0.55))
                .frame(width: 2, height: 4)
        }
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

    /// The module's own data health, independent of whether it currently has a menu
    /// bar item — the builder previews every available module.
    private func previewState(_ id: MetricID) -> MetricDataState {
        model.metricState(for: id, isEnabled: true)
    }
}
