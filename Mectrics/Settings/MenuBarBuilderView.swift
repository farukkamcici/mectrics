import SwiftUI
import MetricsKit

/// Menu bar tab of the settings window.
///
/// The pane reads top-down: the style (separate items or a single icon), a read-only
/// preview of the menu bar as it will look, one row per module for choosing what that
/// module shows, then appearance. Each row is a set of independent chips rather than a
/// single choice, because a module can put several items in the menu bar at once —
/// Battery can show its icon and its health side by side. Every chip draws the real
/// thing it will add, so the choice is made from what can actually be seen. Under the
/// single icon the rows become plain switches for the dashboard's cards instead.
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
                // The Dashboard is one of the things in the menu bar, so it reads
                // as a row in the same list rather than as a switch somewhere else.
                DashboardItemRow(model: model)
                ForEach(model.availableModules, id: \.self) { id in
                    moduleRow(id)
                }
                // The Mac's own card is in the Dashboard like any reading, so it is in
                // this list like any module. It has no live value to draw, so the menu
                // bar is not one of its choices.
                DeviceModuleRow(model: model)
            } header: {
                Text("Modules")
            } footer: {
                Text(
                    String(
                        localized: "builder.modules.placementFooter",
                        defaultValue: "Each module takes its own menu bar item, or a card in the Dashboard. Modules appear only when this Mac reports the required hardware. Temperatures are available inside CPU, Memory, and GPU."
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

        }
        .formStyle(.grouped)
        // Preview tiles are only honest if every module is being sampled, including
        // the ones the user has not added yet.
        .onAppear { model.beginBuilderPreview() }
        .onDisappear { model.endBuilderPreview() }
    }

    // MARK: - Preview strip

    private var previewStrip: some View {
        HStack(spacing: ExperienceSpacing.medium) {
            // The menu bar's own order: the Dashboard first, then every module
            // showing items of its own.
            if model.showsDashboardItem {
                DashboardItemPreview(model: model)
                    .accessibilityElement()
                    .accessibilityLabel(
                        String(
                            localized: "dashboard.statusItem.accessibilityLabel",
                            defaultValue: "Dashboard"
                        )
                    )
            }
            ForEach(model.orderedEnabledItems.indices, id: \.self) { index in
                let entry = model.orderedEnabledItems[index]
                MenuBarPreviewItem(
                    model: model,
                    id: entry.module,
                    component: entry.component
                )
            }
            // An empty menu bar is allowed, and recoverable — but only if you know how,
            // so this says it rather than leaving a blank strip.
            if !model.showsDashboardItem && model.orderedEnabledItems.isEmpty {
                Text(
                    String(
                        localized: "builder.preview.empty",
                        defaultValue: "Nothing in the menu bar. Open Mectrics again from Spotlight to come back here."
                    )
                )
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

    /// One module: where it goes, and — when it takes items of its own — which of them.
    ///
    /// The chips appear whenever the module draws items — on its own or in both places —
    /// and stay hidden otherwise rather than being dimmed: a look it cannot show right
    /// now is not a choice to be made (AGENTS.md §4).
    private func moduleRow(_ id: MetricID) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.small) {
            LabeledContent {
                // A pop-up, not a segmented control: three segments repeated down the
                // whole list read as a wall, and only one of them is ever the answer.
                Picker(
                    String(
                        localized: "builder.placement.label",
                        defaultValue: "Placement"
                    ),
                    selection: Binding(
                        get: { model.placement(of: id) },
                        set: { model.setPlacement($0, for: id) }
                    )
                ) {
                    ForEach(MenuBarPlacement.allCases) { placement in
                        Text(placement.localizedName).tag(placement)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
            } label: {
                HStack(spacing: ExperienceSpacing.small) {
                    Label(
                        id.localizedName,
                        systemImage: MetricSymbol.name(for: id)
                    )
                    ModuleHealthBadge(model: model, id: id)
                }
            }
            if model.placement(of: id).showsOwnItems {
                HStack(spacing: ExperienceSpacing.small) {
                    ForEach(model.availableComponents(for: id)) { component in
                        MenuBarComponentChip(
                            model: model,
                            id: id,
                            component: component
                        )
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// The Dashboard as a row in the modules list.
///
/// It is one of the things the menu bar holds, so it reads like the modules beside it:
/// a name, where it sits, and its contents underneath. What a module shows as component
/// chips, this shows as the readings grouped into it — added and taken out from right
/// here, which is where someone looking at this row expects to do it.
///
/// It is the one row with no placement control, because it is the one item that cannot
/// move: its health badge is the only thing in the app that speaks up unasked, and a
/// menu bar that could be emptied completely would leave no way back into Settings.
private struct DashboardItemRow: View {
    @Bindable var model: AppModel

    private var grouped: [MetricID] { model.orderedDashboardModules }
    private var addable: [MetricID] {
        model.availableModules.filter { model.placement(of: $0) != .grouped }
    }
    /// The Mac's own card is a card like any other, so it is listed and added here too,
    /// under the name the card itself carries.
    private var systemInfoTitle: String { DeviceCardName.localized }
    private var isEmpty: Bool { grouped.isEmpty && !model.showsDeviceCard }
    private var hasAnythingToAdd: Bool { !addable.isEmpty || !model.showsDeviceCard }

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.small) {
            LabeledContent {
                // With cards inside there is nothing to decide — they would have
                // nowhere to be shown — so the place is stated as text and the pop-up
                // appears once it is empty (AGENTS.md §4: disclose, never dim).
                if grouped.isEmpty {
                    Picker(
                        String(
                            localized: "builder.placement.label",
                            defaultValue: "Placement"
                        ),
                        selection: Binding(
                            get: {
                                model.dashboardItemEnabled
                                    ? MenuBarPlacement.ownItems
                                    : .off
                            },
                            set: { model.dashboardItemEnabled = $0 == .ownItems }
                        )
                    ) {
                        Text(MenuBarPlacement.ownItems.localizedName)
                            .tag(MenuBarPlacement.ownItems)
                        Text(MenuBarPlacement.off.localizedName)
                            .tag(MenuBarPlacement.off)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                } else {
                    Text(MenuBarPlacement.ownItems.localizedName)
                        .foregroundStyle(.secondary)
                }
            } label: {
                HStack(spacing: ExperienceSpacing.small) {
                    DashboardItemPreview(model: model)
                    Text(
                        String(
                            localized: "builder.dashboardRow.label",
                            defaultValue: "Dashboard"
                        )
                    )
                }
            }
            contents
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var contents: some View {
        HStack(alignment: .top, spacing: ExperienceSpacing.small) {
            if isEmpty {
                Text(
                    String(
                        localized: "builder.dashboardRow.empty",
                        defaultValue: "Nothing grouped yet — it shows the health badge alone."
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                // Chips keep their natural width and wrap onto another line, so a full
                // Dashboard never squeezes a name into a column of single letters.
                ChipFlowLayout(spacing: ExperienceSpacing.xSmall) {
                    ForEach(grouped, id: \.self) { id in
                        GroupedModuleChip(
                            title: id.localizedName,
                            symbol: MetricSymbol.name(for: id)
                        ) {
                            model.setPlacement(.off, for: id)
                        }
                    }
                    if model.showsDeviceCard {
                        GroupedModuleChip(
                            title: systemInfoTitle,
                            symbol: "desktopcomputer"
                        ) {
                            model.showsDeviceCard = false
                        }
                    }
                }
                // Ahead of the spacer, so the chips fill the row before it takes any.
                .layoutPriority(1)
            }
            Spacer(minLength: 0)
            if hasAnythingToAdd {
                Menu {
                    ForEach(addable, id: \.self) { id in
                        Button(id.localizedName) {
                            model.setPlacement(.grouped, for: id)
                        }
                    }
                    if !model.showsDeviceCard {
                        Button(systemInfoTitle) { model.showsDeviceCard = true }
                    }
                } label: {
                    Label(
                        String(
                            localized: "builder.dashboardRow.add",
                            defaultValue: "Add a reading"
                        ),
                        systemImage: "plus"
                    )
                    .labelStyle(.iconOnly)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(String(
                    localized: "builder.dashboardRow.add",
                    defaultValue: "Add a reading"
                ))
            }
        }
    }
}

/// The Mac's own card as a row in the modules list.
///
/// It sits with the modules because it is one of the things the Dashboard can hold, and
/// a list that showed every reading except this one would leave it adjustable only from
/// inside the popover it appears in. Its placement offers Dashboard and Off and not the
/// menu bar: a macOS version and an uptime are not a reading that changes, and a menu
/// bar item that never moves is a slot spent on nothing.
private struct DeviceModuleRow: View {
    @Bindable var model: AppModel

    var body: some View {
        LabeledContent {
            Picker(
                String(
                    localized: "builder.placement.label",
                    defaultValue: "Placement"
                ),
                selection: Binding(
                    get: { model.showsDeviceCard ? MenuBarPlacement.grouped : .off },
                    set: { model.showsDeviceCard = $0 == .grouped }
                )
            ) {
                Text(MenuBarPlacement.grouped.localizedName)
                    .tag(MenuBarPlacement.grouped)
                Text(MenuBarPlacement.off.localizedName)
                    .tag(MenuBarPlacement.off)
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
        } label: {
            Label(DeviceCardName.localized, systemImage: "desktopcomputer")
        }
        .accessibilityElement(children: .contain)
    }
}

/// One reading inside the Dashboard, with the control that takes it out.
private struct GroupedModuleChip: View {
    let title: String
    let symbol: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: ExperienceSpacing.xSmall) {
            Label(title, systemImage: symbol)
                .labelStyle(.titleAndIcon)
                .font(.caption)
                .lineLimit(1)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    // A real target rather than a glyph's own bounds.
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                String(
                    localized: "builder.dashboardRow.remove",
                    defaultValue: "Remove \(title) from the Dashboard"
                )
            )
        }
        .padding(.leading, ExperienceSpacing.small)
        .padding(.trailing, ExperienceSpacing.xSmall)
        .padding(.vertical, ExperienceSpacing.xSmall)
        .background(
            Capsule().fill(.secondary.opacity(ExperienceSurface.subtleFillOpacity))
        )
        .fixedSize()
        .accessibilityElement(children: .contain)
    }
}

/// Lays chips out left to right at their ideal size, starting a new line when the next
/// one would not fit in the width offered.
private struct ChipFlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let lines = rows(for: subviews, in: proposal.width ?? .infinity)
        let width = lines.map(\.width).max() ?? 0
        let height = lines.map(\.height).reduce(0, +)
            + spacing * CGFloat(max(lines.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var y = bounds.minY
        for row in rows(for: subviews, in: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(for subviews: Subviews, in maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !current.indices.isEmpty,
               current.width + spacing + size.width > maxWidth {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty
                ? size.width
                : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
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
        let isLocked = model.isOnlyEnabledComponent(component, for: id)
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
        // The last look on cannot be switched off — the pop-up is what takes the module
        // out — so the chip says so instead of swallowing the click.
        .disabled(isLocked)
        .help(helpText(isActive: isActive, isLocked: isLocked))
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

    private func helpText(isActive: Bool, isLocked: Bool) -> String {
        if isLocked {
            return String(
                localized: "builder.chip.last",
                defaultValue: "The last look stays on. Use the pop-up to take this module out of the menu bar."
            )
        }
        return isActive
            ? String(localized: "builder.chip.remove", defaultValue: "Click to remove from the menu bar")
            : String(localized: "builder.chip.add", defaultValue: "Click to add to the menu bar")
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

/// The single icon as the menu bar actually draws it: the same template image, badged
/// with the same health state, tinted the same way.
///
/// Reading the real `NSImage` rather than rebuilding the mark in SwiftUI is what keeps
/// the chip honest — there is no second copy of the badge geometry to drift out of step.
/// Its own body reads the health state, which changes on a severity transition and not
/// on a sampling cycle, so this leaf is not a per-cycle cost.
private struct DashboardItemPreview: View {
    let model: AppModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let state = model.healthState
        let isNormal = state == .normal
        // The mark is drawn for an AppKit appearance, and this pane's is the one the
        // chip is being shown in.
        let appearance = NSAppearance(
            named: colorScheme == .dark ? .darkAqua : .aqua
        ) ?? NSAppearance.currentDrawing()
        Image(
            nsImage: MectricsGlyph.menuBarImage(
                badge: isNormal ? nil : state.symbolName,
                tint: state.tint,
                appearance: appearance
            )
        )
        // The badged mark carries its own two colours; only the plain template one is
        // ours to colour.
        .renderingMode(isNormal ? .template : .original)
        .foregroundStyle(Color.primary)
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
        case .valueGraph, .netActivityGraph:
            return textWidth(component, module) + sparklineGap + sparklineWidth
        default:
            return textWidth(component, module)
        }
    }

    private static func textWidth(
        _ component: MenuBarComponent,
        _ module: MetricID
    ) -> CGFloat {
        // The stacked network items are drawn on one line here, so their template is
        // the two rates side by side rather than the single line the menu bar reserves.
        let template = component.drawsStackedRates
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
        case .valueGraph, .netActivityGraph:
            HStack(spacing: ExperienceSpacing.xSmall) {
                previewLabel
                SparklineView(
                    values: model.history(id, count: 30),
                    accent: model.accentColor,
                    scaleFloor: SparklineScale.floor(for: id)
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
