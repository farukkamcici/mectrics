import Foundation
import MetricsKit

// mectrics-cli — a live terminal readout to validate MetricsKit without Xcode.
// Run:   swift run mectrics-cli
// Quit:  Ctrl-C

let store = MetricStore(capacity: 60)
let engine = MetricsEngine(store: store, policy: SamplingPolicy(onACInterval: 1.0))
engine.register(MetricsKit.coreProviders())

func render(_ latest: [MetricID: MetricSample]) {
    // Clear the terminal and move to the top.
    print("\u{1B}[2J\u{1B}[H", terminator: "")
    print("mectrics — live system metrics (Ctrl-C to quit)\n")

    // CPU
    if let cpu = store.latest(.cpu) {
        let hist = store.history(.cpu, count: 40).map(\.normalized)
        let cores = Int(cpu.detail["coreCount"] ?? 0)
        print("CPU     \(MetricFormat.percent(cpu.value, decimals: 1).padding(toLength: 7, withPad: " ", startingAt: 0)) \(MetricFormat.sparkline(hist))  [\(cores) cores]")
    }

    // Memory
    if let mem = store.latest(.memory) {
        let hist = store.history(.memory, count: 40).map(\.normalized)
        let used = mem.detail["used"] ?? 0
        let total = mem.detail["total"] ?? 0
        print("Memory  \(MetricFormat.percent(mem.value, decimals: 1).padding(toLength: 7, withPad: " ", startingAt: 0)) \(MetricFormat.sparkline(hist))  [\(MetricFormat.bytes(used)) / \(MetricFormat.bytes(total))]")
    }

    // Battery
    if let bat = store.latest(.battery) {
        let charging = (bat.detail["charging"] ?? 0) > 0 ? "charging" : "on battery"
        var extra = ""
        if let health = bat.detail["healthPercent"] { extra += "  health \(Int(health))%" }
        if let cycles = bat.detail["cycleCount"] { extra += "  cycles \(Int(cycles))" }
        if let temp = bat.detail["temperature"] { extra += String(format: "  %.1f°C", temp) }
        print("Battery \(MetricFormat.percent(bat.value, decimals: 0).padding(toLength: 7, withPad: " ", startingAt: 0)) \(charging)\(extra)")
    } else {
        print("Battery (no battery on this machine)")
    }

    // Network
    if let net = store.latest(.network) {
        let down = net.detail["down"] ?? 0
        let up = net.detail["up"] ?? 0
        print("Network ↓\(MetricFormat.compactRate(down))/s  ↑\(MetricFormat.compactRate(up))/s")
    }

    // Disk
    if let disk = store.latest(.disk) {
        let used = disk.detail["used"] ?? 0
        let total = disk.detail["total"] ?? 0
        let r = disk.detail["readRate"] ?? 0
        let w = disk.detail["writeRate"] ?? 0
        print("Disk    \(MetricFormat.percent(disk.value, decimals: 0).padding(toLength: 7, withPad: " ", startingAt: 0)) [\(MetricFormat.bytes(used)) / \(MetricFormat.bytes(total))]  R \(MetricFormat.compactRate(r))/s  W \(MetricFormat.compactRate(w))/s")
    }

    // Bluetooth
    if let bt = store.latest(.bluetooth) {
        let count = Int(bt.detail["deviceCount"] ?? 0)
        print("BT      \(count) device(s)  lowest battery \(Int(bt.value * 100))%")
    }

    print("\nSampling: 1s · MetricsKit running ✓")
}

engine.onCycle = { latest in
    render(latest)
}

engine.start()

// Keep the main thread alive.
RunLoop.main.run()
