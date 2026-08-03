import SwiftUI
import MetricsKit

/// Menu bar tab of the settings window.
///
/// The pane reads top-down: a read-only preview of the menu bar as it will look, one
/// row per module for choosing what that module shows, then appearance. Each row is a
/// set of independent chips rather than a single choice, because a module can put
/// several items in the menu bar at once — Battery can show its icon and its health
/// side by side. Every chip draws the real thing it will add, so the choice is made
/// from what can actually be seen.
///
/// **Live values are read only by the small leaf views at the bottom of this file.**
/// Nothing in this view's own body touches `AppModel.latest`, so a new sample cannot
/// invalidate the pane's structure. That is a performance contract, not a style
/// preference: rebuilding the rows once a second means rebuilding every tooltip and
/// hover region with them, and AppKit answers a tracking-area change by re-resolving
/// the pointer — work that grows with how long the pane stays open. Keep every read of
/// a changing value inside a leaf.
struct MenuBarBuilderView: View {
    @Bindable var model: AppModel
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
            } footer: {
                Text(
                    String(
                        localized: "builder.modules.footer",
                        defaultValue: "Modules appear only when this Mac reports the required hardware. Temperatures are available inside CPU, Memory, and GPU."
                    )
                )
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
                        defaultValue: "\(preset.name) · \(count) items"
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
                CompactHealthPreview(model: model)
            }
            ForEach(model.orderedEnabledItems.indices, id: \.self) { index in
                let entry = model.orderedEnabledItems[index]
                MenuBarPreviewItem(
                    model: model,
                    id: entry.module,
                    component: entry.component
                )
            }
            if model.orderedEnabledItems.isEmpty && !model.compactHealthEnabled {
                Text("Nothing in the menu bar yet. Pick a look for a module below.")
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

    // MARK: - Module rows

    private func moduleRow(_ id: MetricID) -> some View {
        LabeledContent {
            HStack(spacing: ExperienceSpacing.small) {
                Spacer(minLength: 0)
                ForEach(model.availableComponents(for: id)) { component in
                    MenuBarComponentChip(
                        model: model,
                        id: id,
                        component: component
                    )
                }
            }
        } label: {
            HStack(spacing: ExperienceSpacing.small) {
                Label(
                    id.localizedName,
                    systemImage: MetricSymbol.name(for: id)
                )
                ModuleHealthBadge(model: model, id: id)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Leaves that read live values

/// One menu bar preview chip in the strip at the top of the pane.
private struct MenuBarPreviewItem: View {
    let model: AppModel
    let id: MetricID
    let component: MenuBarComponent

    var body: some View {
        HStack(spacing: ExperienceSpacing.xSmall) {
            if model.showMenuBarIcons && !component.drawsModuleGlyph {
                Image(systemName: MetricSymbol.name(for: id))
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(model.accentColor)
            }
            MenuBarComponentPreview(
                model: model,
                id: id,
                component: component
            )
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
}

/// One look for one module. Chips are independent: a module can put several items
/// in the menu bar at once, and each chip shows the real thing it will draw.
///
/// The chip's own body reads only the choice — never a sample — so the button, its
/// tooltip, and its hover region survive untouched while the preview inside ticks.
private struct MenuBarComponentChip: View {
    let model: AppModel
    let id: MetricID
    let component: MenuBarComponent
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let isActive = model.isComponentEnabled(component, for: id)
        Button {
            model.toggleComponent(component, for: id)
        } label: {
            VStack(spacing: 3) {
                MenuBarComponentPreview(
                    model: model,
                    id: id,
                    component: component
                )
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
}

/// Only genuine problems earn a badge. "Not in the menu bar" is already visible in
/// the chips themselves. Kept separate so a module's data health can change without
/// rebuilding the row it belongs to.
private struct ModuleHealthBadge: View {
    let model: AppModel
    let id: MetricID

    var body: some View {
        let state = model.metricState(for: id, isEnabled: true)
        if Self.isProblem(state) {
            MetricStatusBadge(state: state)
                .help(state.reason)
        }
    }

    private static func isProblem(_ state: MetricDataState) -> Bool {
        switch state {
        case .live, .disabled, .collecting:
            return false
        case .stale, .error, .permissionRequired, .unavailable:
            return true
        }
    }
}

private struct CompactHealthPreview: View {
    let model: AppModel

    var body: some View {
        let state = model.compactHealthState
        Image(systemName: state.symbolName)
            .accessibilityLabel("Compact Health")
            .accessibilityValue(state.localizedName)
    }
}

/// SwiftUI mirror of the menu bar renderer for one (module, component) pair.
///
/// This is the only view in the pane that reads a live sample, and it reserves a fixed
/// width from the same worst-case template the real item uses. The menu bar reserves
/// that width so items never shift as digits come and go (see `MetricStatusItem`); here
/// it does the same job twice over — the chips stop jiggling, and a new value cannot
/// resize anything, so SwiftUI has no reason to lay the pane out again or hand AppKit a
/// changed hover region.
private struct MenuBarComponentPreview: View {
    let model: AppModel
    let id: MetricID
    let component: MenuBarComponent

    var body: some View {
        content
            .frame(
                width: Self.reservedWidth(for: component, module: id),
                alignment: .trailing
            )
    }

    @ViewBuilder
    private var content: some View {
        if model.latest[id] != nil {
            componentPreview
        } else {
            let state = model.metricState(for: id, isEnabled: true)
            Image(systemName: state.symbolName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(state.tint)
                .accessibilityLabel(state.localizedName)
        }
    }

    // MARK: - Reserved width

    private static let previewFont = NSFont.monospacedDigitSystemFont(
        ofSize: 11,
        weight: .medium
    )
    private static let sparklineWidth: CGFloat = 26
    private static let sparklineGap = ExperienceSpacing.xSmall

    private static func reservedWidth(
        for component: MenuBarComponent,
        module: MetricID
    ) -> CGFloat {
        switch component {
        case .coreBars:         return 36
        case .ring:             return 14
        case .batteryIcon:      return 18
        // Body + gap + terminal nub, as drawn by `labelledBatteryPreview`.
        case .batteryIconValue: return 27
        case .valueGraph:
            return textWidth(component, module) + sparklineGap + sparklineWidth
        default:
            return textWidth(component, module)
        }
    }

    private static func textWidth(
        _ component: MenuBarComponent,
        _ module: MetricID
    ) -> CGFloat {
        // The stacked network item is drawn on one line here, so its template is the
        // two rates side by side rather than the single line the menu bar reserves.
        let template = component == .netActivity
            ? "↓999M ↑999M"
            : component.template(for: module)
        let measured = (template as NSString)
            .size(withAttributes: [.font: previewFont])
            .width
        // Never narrower than the health glyph shown while a module has no sample.
        return max(ceil(measured), 16)
    }

    @ViewBuilder
    private var componentPreview: some View {
        switch component {
        case .valueGraph:
            HStack(spacing: ExperienceSpacing.xSmall) {
                previewLabel
                SparklineView(
                    values: model.history(id, count: 30),
                    accent: model.accentColor
                )
                .frame(width: 26, height: 13)
            }
        case .coreBars:
            CoreBarsView(values: coreValues, accent: model.accentColor)
                .frame(width: 36, height: 14)
        case .ring:
            if let sample = model.latest[id] {
                ringPreview(fraction: sample.value)
            }
        case .batteryIcon:
            Image(systemName: batterySymbol)
                .font(.system(size: 13))
        case .batteryIconValue:
            labelledBatteryPreview
        default:
            previewLabel
        }
    }

    private var previewLabel: some View {
        Text(previewText)
            .font(.system(size: 11, weight: .medium))
            .monospacedDigit()
            .lineLimit(1)
    }

    private var previewText: String {
        guard let sample = model.latest[id] else { return "–" }
        if case .text(let text) = MenuBarText.visual(
            for: id,
            component: component,
            sample: sample,
            temperature: model.temperature(for: id)
        ) {
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
    private var labelledBatteryPreview: some View {
        let sample = model.latest[id]
        let level = min(max(sample?.value ?? 0, 0), 1)
        let charging = (sample?.detail["charging"] ?? 0) > 0
        let charge = Text("\(Int((level * 100).rounded()))")
            .font(.system(size: 7.5, weight: .bold).monospacedDigit())
        return HStack(spacing: 1) {
            ZStack {
                // Solid digits where the body is empty…
                charge
                // …knocked out of the fill where it is not, matching the menu bar.
                ZStack {
                    GeometryReader { proxy in
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(
                                level <= 0.2 && !charging
                                    ? Color.red
                                    : Color.primary.opacity(0.9)
                            )
                            .frame(width: proxy.size.width * level)
                    }
                    .padding(1.8)
                    charge.blendMode(.destinationOut)
                }
                .compositingGroup()
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(.primary.opacity(0.75), lineWidth: 1.2)
            }
            .frame(width: 24, height: 11)
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(.primary.opacity(0.75))
                .frame(width: 2, height: 4)
        }
    }

    private var batterySymbol: String {
        guard let sample = model.latest[id] else { return "battery.0percent" }
        let charging = (sample.detail["charging"] ?? 0) > 0
        if charging { return "battery.100percent.bolt" }
        switch sample.value {
        case ..<0.125:  return "battery.0percent"
        case ..<0.375:  return "battery.25percent"
        case ..<0.625:  return "battery.50percent"
        case ..<0.875:  return "battery.75percent"
        default:        return "battery.100percent"
        }
    }

    private var coreValues: [Double] {
        guard let d = model.latest[id]?.detail else { return [] }
        let cores = Int(d["coreCount"] ?? 0)
        return (0..<cores).compactMap { d["core\($0)"] }
    }
}
