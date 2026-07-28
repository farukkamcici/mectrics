import Foundation
import MetricsKit

// mectrics-cli — MetricsKit'i Xcode'a girmeden doğrulamak için canlı terminal göstergesi.
// Çalıştırma:  swift run mectrics-cli
// Çıkış:       Ctrl-C

let store = MetricStore(capacity: 60)
let engine = MetricsEngine(store: store, policy: SamplingPolicy(onACInterval: 1.0))
engine.register(MetricsKit.coreProviders())

func render(_ latest: [MetricID: MetricSample]) {
    // Terminali temizle ve başa sar.
    print("\u{1B}[2J\u{1B}[H", terminator: "")
    print("mectrics — canlı sistem metrikleri (Ctrl-C ile çık)\n")

    // CPU
    if let cpu = store.latest(.cpu) {
        let hist = store.history(.cpu, count: 40).map(\.normalized)
        let cores = Int(cpu.detail["coreCount"] ?? 0)
        print("CPU     \(MetricFormat.percent(cpu.value, decimals: 1).padding(toLength: 7, withPad: " ", startingAt: 0)) \(MetricFormat.sparkline(hist))  [\(cores) çekirdek]")
    }

    // Bellek
    if let mem = store.latest(.memory) {
        let hist = store.history(.memory, count: 40).map(\.normalized)
        let used = mem.detail["used"] ?? 0
        let total = mem.detail["total"] ?? 0
        print("Bellek  \(MetricFormat.percent(mem.value, decimals: 1).padding(toLength: 7, withPad: " ", startingAt: 0)) \(MetricFormat.sparkline(hist))  [\(MetricFormat.bytes(used)) / \(MetricFormat.bytes(total))]")
    }

    // Pil
    if let bat = store.latest(.battery) {
        let charging = (bat.detail["charging"] ?? 0) > 0 ? "⚡ şarj" : "🔋 pil"
        var extra = ""
        if let health = bat.detail["healthPercent"] { extra += "  sağlık \(Int(health))%" }
        if let cycles = bat.detail["cycleCount"] { extra += "  döngü \(Int(cycles))" }
        if let temp = bat.detail["temperature"] { extra += String(format: "  %.1f°C", temp) }
        print("Pil     \(MetricFormat.percent(bat.value, decimals: 0).padding(toLength: 7, withPad: " ", startingAt: 0)) \(charging)\(extra)")
    } else {
        print("Pil     (bu makinede pil yok)")
    }

    print("\nÖrnekleme: 1sn · MetricsKit çalışıyor ✓")
}

engine.onCycle = { latest in
    render(latest)
}

engine.start()

// Ana thread'i canlı tut.
RunLoop.main.run()
