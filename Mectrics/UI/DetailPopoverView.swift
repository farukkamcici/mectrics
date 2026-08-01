import SwiftUI
import MetricsKit

/// The detail popover shown when a menu bar item is clicked.
struct DetailPopoverView: View {
    @Bindable var model: AppModel
    let moduleID: MetricID
    var showsGlobalActions = true
    var honorsEnabledState = false
    @State private var copyConfirmationVisible = false

    private var sample: MetricSample? { model.latest[moduleID] }
    private var state: MetricDataState {
        model.metricState(
            for: moduleID,
            isEnabled: honorsEnabledState ? nil : true
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.small) {
            header
            Divider()
            if sample == nil {
                MetricEmptyState(
                    state: state,
                    actionTitle: recoveryActionTitle,
                    action: recoveryAction
                )
            } else {
                if state != .live {
                    InlineNotice(
                        state: state,
                        actionTitle: recoveryActionTitle,
                        action: recoveryAction
                    )
                }
                metricContent
            }
            if !contextualActions.isEmpty {
                Divider()
                contextualActionButtons
            }
            if showsGlobalActions {
                Divider()
                footer
            }
        }
        .padding(ExperienceSpacing.medium)
        .frame(width: 290)
    }

    @ViewBuilder
    private var metricContent: some View {
        if moduleID == .disk {
            CapacityBarView(
                used: sample?.detail["used"] ?? 0,
                purgeable: sample?.detail["purgeable"] ?? 0,
                total: sample?.detail["total"] ?? 0,
                accent: model.accentColor
            )
        } else if moduleID != .battery {
            SparklineView(values: model.history(moduleID, count: 60), accent: model.accentColor)
                .frame(height: 40)
        }
        if moduleID == .cpu {
            CoreBarsView(values: coreValues, accent: model.accentColor)
                .frame(height: 24)
        }
        detailRows
        if moduleID == .cpu || moduleID == .memory {
            TopProcessesView(
                mode: moduleID == .cpu ? .cpu : .memory,
                accent: model.accentColor
            )
            .padding(.top, ExperienceSpacing.xSmall)
        }
    }

    /// Per-core usage fractions for the CPU core bars.
    private var coreValues: [Double] {
        guard let d = sample?.detail else { return [] }
        let cores = Int(d["coreCount"] ?? 0)
        return (0..<cores).compactMap { d["core\($0)"] }
    }

    private var header: some View {
        HStack(spacing: ExperienceSpacing.small) {
            Image(systemName: MetricSymbol.name(for: moduleID))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(model.accentColor)
            Text(moduleID.localizedName)
                .font(.headline)
            Spacer()
            VStack(alignment: .trailing, spacing: ExperienceSpacing.xSmall) {
                HStack(spacing: ExperienceSpacing.small) {
                    if sample != nil && (moduleID == .memory || moduleID == .disk) {
                        headerRing
                    }
                    MetricValueText(
                        label: moduleID.localizedName,
                        value: primaryValueString,
                        state: state
                    )
                }
                if state != .live {
                    MetricStatusBadge(state: state)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// Small usage donut next to the value for capacity-style modules.
    private var headerRing: some View {
        ZStack {
            Circle().stroke(
                .secondary.opacity(0.22),
                lineWidth: ExperienceChart.ringStrokeWidth
            )
            Circle()
                .trim(from: 0, to: min(max(sample?.value ?? 0, 0), 1))
                .stroke(
                    model.accentColor,
                    style: StrokeStyle(
                        lineWidth: ExperienceChart.ringStrokeWidth,
                        lineCap: .round
                    )
                )
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 18, height: 18)
    }

    @ViewBuilder
    private var detailRows: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xSmall) {
            ForEach(rows, id: \.0) { row in
                HStack {
                    Text(row.0).foregroundStyle(.secondary)
                    Spacer()
                    Text(row.1).monospacedDigit()
                }
                .font(.callout)
            }
        }
    }

    private var footer: some View {
        PopoverActionBar { model.onOpenSettings?() }
    }

    private var localAddress: (interface: String, address: String)? {
        moduleID == .network ? NetworkInfo.primaryIPv4() : nil
    }

    private var contextualActions: [MetricContextualAction] {
        MetricContextualAction.actions(
            for: moduleID,
            hasLocalAddress: localAddress != nil
        )
    }

    private var contextualActionButtons: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xSmall) {
            ForEach(contextualActions, id: \.self) { action in
                PopoverPrimaryButton(
                    title: action.title,
                    symbolName: action.symbolName
                ) {
                    let succeeded = MetricContextualActionRunner.run(
                        action,
                        localAddress: localAddress
                    )
                    copyConfirmationVisible =
                        action == .copyLocalAddress && succeeded
                }
            }
            if copyConfirmationVisible {
                Label(
                    String(
                        localized: "net.localAddressCopied",
                        defaultValue: "Local address copied."
                    ),
                    systemImage: "checkmark"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isStaticText)
            }
        }
        .font(.callout)
    }

    private var recoveryActionTitle: String? {
        switch state {
        case .collecting, .stale, .error:
            return String(localized: "state.action.refresh", defaultValue: "Refresh")
        case .permissionRequired:
            return String(
                localized: "state.action.openSystemSettings",
                defaultValue: "Open System Settings"
            )
        case .disabled:
            return String(localized: "state.action.enable", defaultValue: "Enable")
        default:
            return nil
        }
    }

    private var recoveryAction: (() -> Void)? {
        switch state {
        case .collecting, .stale, .error:
            return { model.refreshMetrics() }
        case .permissionRequired:
            return {
                guard let url = URL(
                    string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension"
                ) else { return }
                NSWorkspace.shared.open(url)
            }
        case .disabled:
            return { model.setEnabled(true, for: moduleID) }
        default:
            return nil
        }
    }

    // MARK: - Value formatting

    private var primaryValueString: String {
        guard let sample else { return "–" }
        switch moduleID {
        case .cpu, .memory, .disk, .gpu:
            return MetricFormat.percent(sample.value, decimals: 1)
        case .battery:
            return "\(Int((sample.value * 100).rounded()))%"
        case .fans:
            return "\(Int((sample.detail["maxRpm"] ?? 0).rounded())) RPM"
        case .network:
            return MetricFormat.bytesPerSecond(sample.value)
        case .sensors:
            return String(format: "%.1f°C", sample.value)
        }
    }

    /// Row label/value pairs. Labels are localized; values are numeric/units.
    private var rows: [(String, String)] {
        guard let sample else { return [] }
        let d = sample.detail
        switch moduleID {
        case .cpu:
            var r: [(String, String)] = [
                (String(localized: "cpu.cores", defaultValue: "Cores"), "\(Int(d["coreCount"] ?? 0))")
            ]
            let cores = Int(d["coreCount"] ?? 0)
            let perCore = (0..<cores).compactMap { d["core\($0)"] }
            if let maxCore = perCore.max() {
                r.append((String(localized: "cpu.busiestCore", defaultValue: "Busiest core"),
                          MetricFormat.percent(maxCore, decimals: 0)))
            }
            // Hardware-domain grouping: the CPU temperature lives here, not in a
            // separate sensors module.
            if let t = model.latest[.sensors]?.detail["cpuMax"] {
                r.append((String(localized: "cpu.temperature", defaultValue: "Temperature"),
                          String(format: "%.1f°C", t)))
            }
            r.append((String(localized: "cpu.uptime", defaultValue: "Uptime"),
                      Self.uptimeString))
            return r
        case .memory:
            var r: [(String, String)] = [
                (String(localized: "mem.used", defaultValue: "Used"), MetricFormat.bytes(d["used"] ?? 0)),
                (String(localized: "mem.total", defaultValue: "Total"), MetricFormat.bytes(d["total"] ?? 0)),
                (String(localized: "mem.wired", defaultValue: "Wired"), MetricFormat.bytes(d["wired"] ?? 0)),
                (String(localized: "mem.compressed", defaultValue: "Compressed"), MetricFormat.bytes(d["compressed"] ?? 0)),
                (String(localized: "mem.free", defaultValue: "Free"), MetricFormat.bytes(d["free"] ?? 0))
            ]
            if let swapTotal = d["swapTotal"], swapTotal > 0 {
                let used = MetricFormat.bytes(d["swapUsed"] ?? 0)
                r.append((String(localized: "mem.swap", defaultValue: "Swap"),
                          "\(used) / \(MetricFormat.bytes(swapTotal))"))
            }
            if let level = d["pressureLevel"] {
                r.append((String(localized: "mem.pressure", defaultValue: "Pressure"),
                          Self.pressureLabel(level)))
            }
            if let t = model.temperature(for: .memory) {
                r.append((String(localized: "mem.temperature", defaultValue: "Temperature"),
                          String(format: "%.1f°C", t)))
            }
            return r
        case .battery:
            let charging = (d["charging"] ?? 0) > 0
            let chargingLabel = charging
                ? String(localized: "battery.charging", defaultValue: "Charging")
                : String(localized: "battery.onBattery", defaultValue: "On battery")
            var r: [(String, String)] = [
                (String(localized: "battery.status", defaultValue: "Status"), chargingLabel)
            ]
            // Time estimate: IOPS value first, AppleSmartBattery TimeRemaining as
            // fallback; macOS sometimes has no estimate at all ("Calculating…").
            let ips = charging ? d["timeToFull"] : d["timeToEmpty"]
            let estimate = (ips ?? -1) > 0 ? ips : d["smartTimeRemaining"]
            let label = charging
                ? String(localized: "battery.timeToFull", defaultValue: "Time to full")
                : String(localized: "battery.timeRemaining", defaultValue: "Time remaining")
            if let estimate, estimate > 0 {
                r.append((label, Self.minutesString(estimate)))
            } else {
                r.append((label, String(localized: "battery.calculating", defaultValue: "Calculating…")))
            }
            if let h = d["healthPercent"] {
                r.append((String(localized: "battery.health", defaultValue: "Health"), "\(Int(h))%"))
            }
            if let c = d["cycleCount"] {
                r.append((String(localized: "battery.cycles", defaultValue: "Charge cycles"), "\(Int(c))"))
            }
            if let t = d["temperature"] {
                r.append((String(localized: "battery.temp", defaultValue: "Temperature"), String(format: "%.1f°C", t)))
            }
            return r
        case .network:
            var r: [(String, String)] = [
                (String(localized: "net.down", defaultValue: "Download"), MetricFormat.bytesPerSecond(d["down"] ?? 0)),
                (String(localized: "net.up", defaultValue: "Upload"), MetricFormat.bytesPerSecond(d["up"] ?? 0)),
                (String(localized: "net.totalDown", defaultValue: "Total downloaded"), MetricFormat.bytes(d["downTotal"] ?? 0)),
                (String(localized: "net.totalUp", defaultValue: "Total uploaded"), MetricFormat.bytes(d["upTotal"] ?? 0))
            ]
            if let info = NetworkInfo.primaryIPv4() {
                r.append((String(localized: "net.localIP", defaultValue: "Local IP"),
                          "\(info.address) (\(info.interface))"))
            }
            return r
        case .disk:
            var r: [(String, String)] = [
                (String(localized: "disk.used", defaultValue: "Used"), MetricFormat.bytes(d["used"] ?? 0)),
                (String(localized: "disk.free", defaultValue: "Free"), MetricFormat.bytes(d["free"] ?? 0))
            ]
            if let purgeable = d["purgeable"], purgeable > 0 {
                r.append((String(localized: "disk.purgeable", defaultValue: "Purgeable"),
                          MetricFormat.bytes(purgeable)))
            }
            r.append(
                (
                    String(localized: "disk.total", defaultValue: "Total"),
                    MetricFormat.bytes(d["total"] ?? 0)
                )
            )
            if let readRate = d["readRate"], let writeRate = d["writeRate"] {
                r.append(
                    (
                        String(localized: "disk.read", defaultValue: "Read"),
                        MetricFormat.bytesPerSecond(readRate)
                    )
                )
                r.append(
                    (
                        String(localized: "disk.write", defaultValue: "Write"),
                        MetricFormat.bytesPerSecond(writeRate)
                    )
                )
            }
            return r
        case .gpu:
            var r: [(String, String)] = [
                (String(localized: "gpu.count", defaultValue: "GPUs"), "\(Int(d["gpuCount"] ?? 1))")
            ]
            if let mem = d["inUseMemory"], mem > 0 {
                r.append((String(localized: "gpu.memory", defaultValue: "In-use memory"),
                          MetricFormat.bytes(mem)))
            }
            if let t = model.latest[.sensors]?.detail["gpuMax"] {
                r.append((String(localized: "gpu.temperature", defaultValue: "Temperature"),
                          String(format: "%.1f°C", t)))
            }
            return r
        case .sensors:
            var r: [(String, String)] = []
            if let c = d["cpuMax"] {
                r.append((String(localized: "sensors.cpu", defaultValue: "CPU (hottest)"),
                          String(format: "%.1f°C", c)))
            }
            if let g = d["gpuMax"] {
                r.append((String(localized: "sensors.gpu", defaultValue: "GPU (hottest)"),
                          String(format: "%.1f°C", g)))
            }
            if let m = d["memoryMax"] {
                r.append((String(localized: "sensors.memory", defaultValue: "Memory (hottest)"),
                          String(format: "%.1f°C", m)))
            }
            r.append((String(localized: "sensors.count", defaultValue: "Sensors"),
                      "\(Int(d["sensorCount"] ?? 0))"))
            return r
        case .fans:
            var r: [(String, String)] = [
                (String(localized: "fans.count", defaultValue: "Fans"), "\(Int(d["fanCount"] ?? 0))")
            ]
            let count = Int(d["fanCount"] ?? 0)
            for i in 0..<count {
                if let rpm = d["fan\(i)Rpm"] {
                    let label = String(localized: "fans.fan", defaultValue: "Fan \(i + 1)")
                    r.append((label, "\(Int(rpm)) RPM"))
                }
            }
            return r
        }
    }

    // MARK: - System info formatting

    /// Minutes → "2h 15m" / "45m".
    private static func minutesString(_ minutes: Double) -> String {
        let total = Int(minutes)
        let hours = total / 60
        let mins = total % 60
        return hours > 0 ? "\(hours)h \(mins)m" : "\(mins)m"
    }

    private static var uptimeString: String {
        let uptime = Int(ProcessInfo.processInfo.systemUptime)
        let days = uptime / 86_400
        let hours = (uptime % 86_400) / 3_600
        let minutes = (uptime % 3_600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    /// Kernel pressure level (1/2/4) → user-facing label. A value the kernel does not
    /// define is shown as a dash rather than guessed at.
    private static func pressureLabel(_ level: Double) -> String {
        MemoryPressureLevel(rawValue: Int(level))?.localizedName ?? "–"
    }
}

private extension MetricContextualAction {
    var title: String {
        switch self {
        case .activityMonitor:
            return String(
                localized: "action.openActivityMonitor",
                defaultValue: "Open Activity Monitor"
            )
        case .storageSettings:
            return String(
                localized: "action.openStorageSettings",
                defaultValue: "Open Storage Settings"
            )
        case .batterySettings:
            return String(
                localized: "action.openBatterySettings",
                defaultValue: "Open Battery Settings"
            )
        case .networkSettings:
            return String(
                localized: "action.openNetworkSettings",
                defaultValue: "Open Network Settings"
            )
        case .copyLocalAddress:
            return String(
                localized: "action.copyLocalAddress",
                defaultValue: "Copy Local Address"
            )
        }
    }

    var symbolName: String {
        switch self {
        case .activityMonitor: return "gauge.with.dots.needle.67percent"
        case .storageSettings: return "internaldrive"
        case .batterySettings: return "battery.100percent"
        case .networkSettings: return "network"
        case .copyLocalAddress: return "doc.on.doc"
        }
    }
}

/// Horizontal capacity breakdown for the Disk popover: used / purgeable / free
/// segments with a compact legend.
private struct CapacityBarView: View {
    let used: Double
    let purgeable: Double
    let total: Double
    var accent: Color
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.small) {
            GeometryReader { geo in
                HStack(spacing: ExperienceSpacing.hairline) {
                    segment(
                        width: geo.size.width,
                        fraction: usedStrict,
                        color: accent,
                        outlined: false
                    )
                    segment(width: geo.size.width, fraction: purgeableFraction,
                            color: accent.opacity(0.35), outlined: differentiateWithoutColor)
                    segment(width: geo.size.width, fraction: freeFraction,
                            color: .secondary.opacity(0.15), outlined: true)
                }
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: ExperienceRadius.compact,
                        style: .continuous
                    )
                )
            }
            .frame(height: 14)
            HStack(spacing: ExperienceSpacing.medium) {
                legend(color: accent,
                       label: String(localized: "disk.legend.used", defaultValue: "Used"))
                if purgeable > 0 {
                    legend(color: accent.opacity(0.35),
                           label: String(localized: "disk.legend.purgeable", defaultValue: "Purgeable"))
                }
                legend(color: .secondary.opacity(0.3),
                       label: String(localized: "disk.legend.free", defaultValue: "Free"))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            String(localized: "disk.capacityChart", defaultValue: "Disk capacity")
        )
        .accessibilityValue(accessibilitySummary)
    }

    // "Used" reported by the provider already excludes purgeable; draw the three
    // segments so they sum to the full width.
    private var usedStrict: Double { total > 0 ? min(used / total, 1) : 0 }
    private var purgeableFraction: Double { total > 0 ? min(purgeable / total, 1) : 0 }
    private var freeFraction: Double { max(1 - usedStrict - purgeableFraction, 0) }

    private func segment(
        width: CGFloat,
        fraction: Double,
        color: Color,
        outlined: Bool
    ) -> some View {
        Rectangle()
            .fill(color)
            .overlay {
                if outlined {
                    Rectangle().strokeBorder(
                        .primary.opacity(
                            contrast == .increased
                                ? ExperienceSurface.increasedBorderOpacity
                                : ExperienceSurface.standardBorderOpacity
                        )
                    )
                }
            }
            .frame(
                width: max(
                    width * CGFloat(fraction),
                    fraction > 0 ? ExperienceSpacing.tiny : 0
                )
            )
    }

    private func legend(color: Color, label: String) -> some View {
        HStack(spacing: ExperienceSpacing.xSmall) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
        }
    }

    private var accessibilitySummary: String {
        let format = String(
            localized: "disk.capacityChart.summary",
            defaultValue: "Used %.0f%%, purgeable %.0f%%, free %.0f%%"
        )
        return String(
            format: format,
            usedStrict * 100,
            purgeableFraction * 100,
            freeFraction * 100
        )
    }
}
