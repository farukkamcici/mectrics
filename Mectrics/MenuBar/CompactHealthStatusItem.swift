import AppKit
import MetricsKit
import SwiftUI

struct ActiveAlertCondition: Equatable, Identifiable {
    var id: String { conditionKey }
    let conditionKey: String
    let metricID: MetricID
    let state: AlertConditionState
    let severity: AttentionSeverity
    let startedAt: Date
    let measuredValue: Double
    let thresholdValue: Double
    let unit: MetricUnit
    let destinations: Set<AlertDestination>

    init(update: AlertConditionUpdate) {
        conditionKey = update.conditionKey
        metricID = update.metricID
        state = update.state
        severity = Self.severity(for: update)
        startedAt = update.startedAt ?? Date()
        measuredValue = update.measuredValue
        thresholdValue = update.thresholdValue
        unit = update.unit
        destinations = update.destinations
    }

    private static func severity(
        for update: AlertConditionUpdate
    ) -> AttentionSeverity {
        guard update.state == .active else { return .info }
        if update.conditionKey == SystemAlertSignal.thermalState.conditionKey,
           update.measuredValue >= 3 {
            return .critical
        }
        if update.conditionKey == SystemAlertSignal.memoryPressure.conditionKey,
           update.measuredValue >= 4 {
            return .critical
        }
        return .warning
    }
}

enum CompactHealthState: String, CaseIterable, Equatable {
    case normal
    case pending
    case warning
    case critical
    case stale
    case unavailable

    static func resolve(
        conditions: [ActiveAlertCondition],
        configuredMetricStates: [MetricDataState]
    ) -> Self {
        if conditions.contains(where: { $0.severity == .critical }) {
            return .critical
        }
        if conditions.contains(where: { $0.state == .active }) {
            return .warning
        }
        if conditions.contains(where: { $0.state == .pending }) {
            return .pending
        }
        if configuredMetricStates.contains(.stale) {
            return .stale
        }
        if !configuredMetricStates.isEmpty,
           configuredMetricStates.allSatisfy({
               $0 == .unavailable || $0 == .permissionRequired
           }) {
            return .unavailable
        }
        return .normal
    }

    var symbolName: String {
        switch self {
        case .normal: return "checkmark.shield"
        case .pending: return "clock.badge"
        case .warning: return "exclamationmark.triangle"
        case .critical: return "exclamationmark.octagon.fill"
        case .stale: return "clock.arrow.trianglehead.counterclockwise.rotate.90"
        case .unavailable: return "questionmark.circle"
        }
    }

    var localizedName: String {
        switch self {
        case .normal:
            return String(
                localized: "health.state.normal",
                defaultValue: "All systems normal"
            )
        case .pending:
            return String(
                localized: "health.state.pending",
                defaultValue: "A condition is pending"
            )
        case .warning:
            return String(
                localized: "health.state.warning",
                defaultValue: "Attention recommended"
            )
        case .critical:
            return String(
                localized: "health.state.critical",
                defaultValue: "Critical attention needed"
            )
        case .stale:
            return String(
                localized: "health.state.stale",
                defaultValue: "Some readings are stale"
            )
        case .unavailable:
            return String(
                localized: "health.state.unavailable",
                defaultValue: "Selected readings are unavailable"
            )
        }
    }

    var tint: NSColor {
        switch self {
        case .normal: return .labelColor
        case .pending, .stale: return .systemOrange
        case .warning: return .systemOrange
        case .critical: return .systemRed
        case .unavailable: return .secondaryLabelColor
        }
    }
}

/// Stable-width status item whose shape, accessibility value, and popover copy all
/// communicate state without depending on color.
@MainActor
final class CompactHealthStatusItem: NSObject {
    static let fixedLength: CGFloat = 26

    let item = NSStatusBar.system.statusItem(
        withLength: CompactHealthStatusItem.fixedLength
    )
    var onClick: (() -> Void)?

    override init() {
        super.init()
        item.autosaveName = "mectrics.compactHealth"
        item.isVisible = true
        item.button?.target = self
        item.button?.action = #selector(clicked)
        item.button?.imagePosition = .imageOnly
    }

    func update(_ state: CompactHealthState) {
        guard let button = item.button else { return }
        let configuration = NSImage.SymbolConfiguration(
            pointSize: 13,
            weight: .medium
        )
        let image = NSImage(
            systemSymbolName: state.symbolName,
            accessibilityDescription: nil
        )?.withSymbolConfiguration(configuration)
        image?.isTemplate = state == .normal
        if state == .normal {
            button.contentTintColor = nil
        } else {
            button.contentTintColor = state.tint
        }
        button.image = image
        button.setAccessibilityLabel(
            String(
                localized: "health.accessibility.label",
                defaultValue: "Mectrics health"
            )
        )
        button.setAccessibilityValue(state.localizedName)
        button.toolTip = state.localizedName
    }

    func remove() {
        NSStatusBar.system.removeStatusItem(item)
    }

    @objc private func clicked() {
        onClick?()
    }
}

struct CompactHealthPopoverView: View {
    @Bindable var model: AppModel
    @State private var summaryCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.medium) {
            Label(
                model.compactHealthState.localizedName,
                systemImage: model.compactHealthState.symbolName
            )
            .font(.headline)

            if model.compactHealthConditions.isEmpty {
                Text("Mectrics will show selected alert conditions here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: ExperienceSpacing.small) {
                    ForEach(model.compactHealthConditions.prefix(3)) { condition in
                        Button {
                            model.onOpenMetricDetail?(condition.metricID)
                        } label: {
                            HStack {
                                Image(systemName: condition.severity.symbolName)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading) {
                                    Text(condition.metricID.localizedName)
                                        .font(.callout.weight(.medium))
                                    Text(condition.summary)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            "\(condition.metricID.localizedName), \(condition.summary)"
                        )
                    }
                }
            }

            Divider()
            VStack(alignment: .leading, spacing: ExperienceSpacing.small) {
                ForEach(model.orderedEnabledModules.prefix(4), id: \.self) { id in
                    Button {
                        model.onOpenMetricDetail?(id)
                    } label: {
                        HStack {
                            Label(
                                id.localizedName,
                                systemImage: FloatingPanelView.symbol(for: id)
                            )
                            Spacer()
                            Text(moduleValue(id))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            Button("Open Attention Log") {
                model.onOpenAttentionLog?()
            }
            Button("Copy System Summary") {
                summaryCopied = SystemSummaryBuilder.copy(model: model)
            }
            if summaryCopied {
                Text("System summary copied.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(ExperienceSpacing.large)
        .frame(width: 320)
    }

    private func moduleValue(_ id: MetricID) -> String {
        guard let sample = model.latest[id] else {
            return model.metricState(
                for: id,
                isEnabled: true
            ).localizedName
        }
        switch sample.unit {
        case .fraction:
            return MetricFormat.percent(sample.value)
        case .percent:
            return "\(Int(sample.value.rounded()))%"
        case .celsius:
            return "\(Int(sample.value.rounded()))°C"
        default:
            return sample.value.formatted(.number.precision(.fractionLength(1)))
        }
    }
}

extension AttentionSeverity {
    var rank: Int {
        switch self {
        case .info: return 0
        case .warning: return 1
        case .critical: return 2
        }
    }

    var symbolName: String {
        switch self {
        case .info: return "clock"
        case .warning: return "exclamationmark.triangle"
        case .critical: return "exclamationmark.octagon.fill"
        }
    }
}

private extension ActiveAlertCondition {
    var summary: String {
        switch conditionKey {
        case SystemAlertSignal.memoryPressure.conditionKey:
            return String(
                localized: "health.condition.memoryPressure",
                defaultValue: "Memory pressure is \(SystemSignalFormat.pressure(measuredValue))"
            )
        case SystemAlertSignal.diskAvailableCapacity.conditionKey:
            return String(
                localized: "health.condition.diskCapacity",
                defaultValue: "\(MetricFormat.bytes(measuredValue)) disk space remains"
            )
        case SystemAlertSignal.thermalState.conditionKey:
            return String(
                localized: "health.condition.thermal",
                defaultValue: "Thermal state is \(SystemSignalFormat.thermal(measuredValue))"
            )
        case SystemAlertSignal.batteryService.conditionKey:
            return String(
                localized: "health.condition.batteryService",
                defaultValue: "macOS recommends battery service"
            )
        default:
            let value = unit == .celsius
                ? "\(Int(measuredValue.rounded()))°C"
                : "\(Int(measuredValue.rounded()))%"
            return state == .pending
                ? String(
                    localized: "health.condition.pending",
                    defaultValue: "\(value), waiting for sustained duration"
                )
                : String(
                    localized: "health.condition.active",
                    defaultValue: "\(value), threshold crossed"
                )
        }
    }
}
