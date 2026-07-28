import SwiftUI
import MetricsKit

/// The detail popover shown when a menu bar item is clicked.
struct DetailPopoverView: View {
    @Bindable var model: AppModel
    let moduleID: MetricID
    @Environment(\.openSettings) private var openSettings

    private var sample: MetricSample? { model.latest[moduleID] }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header
            Divider()
            if moduleID == .disk {
                // Capacity barely moves on a 60 s timeline — show the breakdown instead.
                CapacityBarView(
                    used: sample?.detail["used"] ?? 0,
                    purgeable: sample?.detail["purgeable"] ?? 0,
                    total: sample?.detail["total"] ?? 0,
                    accent: model.accentColor
                )
            } else {
                SparklineView(values: model.history(moduleID, count: 60), accent: model.accentColor)
                    .frame(height: 40)
            }
            if moduleID == .cpu {
                CoreBarsView(values: coreValues, accent: model.accentColor)
                    .frame(height: 24)
            }
            detailRows
            if moduleID == .cpu || moduleID == .memory {
                Divider()
                TopProcessesView(mode: moduleID == .cpu ? .cpu : .memory,
                                 accent: model.accentColor)
            }
            Divider()
            footer
        }
        .padding(11)
        .frame(width: 290)
    }

    /// Per-core usage fractions for the CPU core bars.
    private var coreValues: [Double] {
        guard let d = sample?.detail else { return [] }
        let cores = Int(d["coreCount"] ?? 0)
        return (0..<cores).compactMap { d["core\($0)"] }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: FloatingPanelView.symbol(for: moduleID))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(model.accentColor)
            Text(moduleID.localizedName)
                .font(.headline)
            Spacer()
            if moduleID == .memory || moduleID == .disk {
                headerRing
            }
            Text(primaryValueString)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundStyle(.primary)
                .monospacedDigit()
        }
    }

    /// Small usage donut next to the value for capacity-style modules.
    private var headerRing: some View {
        ZStack {
            Circle().stroke(.secondary.opacity(0.22), lineWidth: 3)
            Circle()
                .trim(from: 0, to: min(max(sample?.value ?? 0, 0), 1))
                .stroke(model.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 18, height: 18)
    }

    @ViewBuilder
    private var detailRows: some View {
        VStack(alignment: .leading, spacing: 5) {
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
        HStack {
            Button {
                // Menu bar agent: activate the app first, otherwise the settings
                // window opens behind the frontmost app (or not at all).
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            Spacer()
            Button {
                model.showFloatingPanel.toggle()
            } label: {
                Label(model.showFloatingPanel ? "Hide panel" : "Show panel",
                      systemImage: "rectangle.portrait.on.rectangle.portrait")
            }
            Spacer()
            Button(role: .destructive) {
                NSApp.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
            }
        }
        .font(.callout)
    }

    // MARK: - Value formatting

    private var primaryValueString: String {
        guard let sample else { return "—" }
        switch moduleID {
        case .cpu, .memory, .disk, .gpu:
            return MetricFormat.percent(sample.value, decimals: 1)
        case .battery, .bluetooth, .fans:
            return "\(Int((sample.value * 100).rounded()))%"
        case .network:
            return MetricFormat.bytesPerSecond(sample.value)
        case .sensors:
            return String(format: "%.1f°C", sample.value)
        default:
            return MetricFormat.percent(sample.value, decimals: 0)
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
            return r
        case .battery:
            let charging = (d["charging"] ?? 0) > 0
            let chargingLabel = charging
                ? String(localized: "battery.charging", defaultValue: "Charging")
                : String(localized: "battery.onBattery", defaultValue: "On battery")
            var r: [(String, String)] = [
                (String(localized: "battery.status", defaultValue: "Status"), chargingLabel)
            ]
            // Time estimates: -1 means "still calculating"; show whichever applies.
            if charging, let t = d["timeToFull"], t > 0 {
                r.append((String(localized: "battery.timeToFull", defaultValue: "Time to full"),
                          Self.minutesString(t)))
            } else if !charging, let t = d["timeToEmpty"], t > 0 {
                r.append((String(localized: "battery.timeRemaining", defaultValue: "Time remaining"),
                          Self.minutesString(t)))
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
            r += [
                (String(localized: "disk.total", defaultValue: "Total"), MetricFormat.bytes(d["total"] ?? 0)),
                (String(localized: "disk.read", defaultValue: "Read"), MetricFormat.bytesPerSecond(d["readRate"] ?? 0)),
                (String(localized: "disk.write", defaultValue: "Write"), MetricFormat.bytesPerSecond(d["writeRate"] ?? 0))
            ]
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
        case .bluetooth:
            var r: [(String, String)] = [
                (String(localized: "bt.deviceCount", defaultValue: "Device count"), "\(Int(d["deviceCount"] ?? 0))")
            ]
            let count = Int(d["deviceCount"] ?? 0)
            let names = BluetoothProvider.latestDeviceNames()
            for i in 0..<count {
                if let pct = d["device\(i)"] {
                    let fallback = String(localized: "bt.device", defaultValue: "Device \(i + 1)")
                    let name = i < names.count && !names[i].isEmpty ? names[i] : fallback
                    r.append((name, "\(Int(pct))%"))
                }
            }
            return r
        default:
            return []
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

    /// Kernel pressure level (1/2/4) → user-facing label.
    private static func pressureLabel(_ level: Double) -> String {
        switch Int(level) {
        case 1:  return String(localized: "pressure.normal", defaultValue: "Normal")
        case 2:  return String(localized: "pressure.warning", defaultValue: "Warning")
        case 4:  return String(localized: "pressure.critical", defaultValue: "Critical")
        default: return "—"
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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                HStack(spacing: 1) {
                    segment(width: geo.size.width, fraction: usedStrict, color: accent)
                    segment(width: geo.size.width, fraction: purgeableFraction,
                            color: accent.opacity(0.35))
                    segment(width: geo.size.width, fraction: freeFraction,
                            color: .secondary.opacity(0.15))
                }
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            .frame(height: 14)
            HStack(spacing: 12) {
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
    }

    // "Used" reported by the provider already excludes purgeable; draw the three
    // segments so they sum to the full width.
    private var usedStrict: Double { total > 0 ? min(used / total, 1) : 0 }
    private var purgeableFraction: Double { total > 0 ? min(purgeable / total, 1) : 0 }
    private var freeFraction: Double { max(1 - usedStrict - purgeableFraction, 0) }

    private func segment(width: CGFloat, fraction: Double, color: Color) -> some View {
        Rectangle()
            .fill(color)
            .frame(width: max(width * CGFloat(fraction), fraction > 0 ? 2 : 0))
    }

    private func legend(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
        }
    }
}
