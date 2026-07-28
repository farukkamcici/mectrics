import SwiftUI
import MetricsKit

/// Menü çubuğu öğesine tıklanınca açılan detay popover'ı.
struct DetailPopoverView: View {
    @Bindable var model: AppModel
    let moduleID: MetricID

    private var sample: MetricSample? { model.latest[moduleID] }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            SparklineView(values: model.history(moduleID, count: 60))
                .frame(height: 44)
            detailRows
            Spacer(minLength: 0)
            footer
        }
        .padding(14)
        .frame(width: 300, height: 260)
    }

    private var header: some View {
        HStack {
            Text(moduleID.displayName)
                .font(.headline)
            Spacer()
            Text(primaryValueString)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundStyle(.primary)
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private var detailRows: some View {
        VStack(alignment: .leading, spacing: 6) {
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
            SettingsLink {
                Label("Ayarlar", systemImage: "gearshape")
            }
            Spacer()
            Button(role: .destructive) {
                NSApp.terminate(nil)
            } label: {
                Label("Çıkış", systemImage: "power")
            }
        }
        .font(.callout)
    }

    // MARK: - Değer biçimleme

    private var primaryValueString: String {
        guard let sample else { return "—" }
        switch moduleID {
        case .cpu, .memory, .disk:
            return MetricFormat.percent(sample.value, decimals: 1)
        case .battery, .bluetooth:
            return "\(Int((sample.value * 100).rounded()))%"
        case .network:
            return MetricFormat.bytesPerSecond(sample.value)
        default:
            return MetricFormat.percent(sample.value, decimals: 0)
        }
    }

    private var rows: [(String, String)] {
        guard let sample else { return [] }
        let d = sample.detail
        switch moduleID {
        case .cpu:
            var r: [(String, String)] = [("Çekirdek sayısı", "\(Int(d["coreCount"] ?? 0))")]
            let cores = Int(d["coreCount"] ?? 0)
            let perCore = (0..<cores).compactMap { d["core\($0)"] }
            if let maxCore = perCore.max() {
                r.append(("En yüklü çekirdek", MetricFormat.percent(maxCore, decimals: 0)))
            }
            return r
        case .memory:
            return [
                ("Kullanılan", MetricFormat.bytes(d["used"] ?? 0)),
                ("Toplam", MetricFormat.bytes(d["total"] ?? 0)),
                ("Wired", MetricFormat.bytes(d["wired"] ?? 0)),
                ("Sıkıştırılmış", MetricFormat.bytes(d["compressed"] ?? 0)),
                ("Boş", MetricFormat.bytes(d["free"] ?? 0))
            ]
        case .battery:
            var r: [(String, String)] = []
            r.append(("Durum", (d["charging"] ?? 0) > 0 ? "Şarj oluyor" : "Pilde"))
            if let h = d["healthPercent"] { r.append(("Sağlık", "\(Int(h))%")) }
            if let c = d["cycleCount"] { r.append(("Şarj döngüsü", "\(Int(c))")) }
            if let t = d["temperature"] { r.append(("Sıcaklık", String(format: "%.1f°C", t))) }
            return r
        case .network:
            return [
                ("İndirme", MetricFormat.bytesPerSecond(d["down"] ?? 0)),
                ("Yükleme", MetricFormat.bytesPerSecond(d["up"] ?? 0)),
                ("Toplam indirilen", MetricFormat.bytes(d["downTotal"] ?? 0)),
                ("Toplam yüklenen", MetricFormat.bytes(d["upTotal"] ?? 0))
            ]
        case .disk:
            return [
                ("Kullanılan", MetricFormat.bytes(d["used"] ?? 0)),
                ("Boş", MetricFormat.bytes(d["free"] ?? 0)),
                ("Toplam", MetricFormat.bytes(d["total"] ?? 0)),
                ("Okuma", MetricFormat.bytesPerSecond(d["readRate"] ?? 0)),
                ("Yazma", MetricFormat.bytesPerSecond(d["writeRate"] ?? 0))
            ]
        case .bluetooth:
            var r: [(String, String)] = [("Cihaz sayısı", "\(Int(d["deviceCount"] ?? 0))")]
            let count = Int(d["deviceCount"] ?? 0)
            for i in 0..<count {
                if let pct = d["device\(i)"] {
                    r.append(("Cihaz \(i + 1)", "\(Int(pct))%"))
                }
            }
            return r
        default:
            return []
        }
    }
}
