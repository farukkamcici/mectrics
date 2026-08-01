import Foundation
import MetricsKit

// Internal live readout for validating MetricsKit providers without the app.
// Run:   swift run metricskit-demo
// Quit:  Ctrl-C

let store = MetricStore(capacity: 60)
let engine = MetricsEngine(
    store: store,
    policy: SamplingPolicy(onACInterval: 1.0)
)
engine.register(MetricsKit.coreProviders())

func padded(_ value: String) -> String {
    value.padding(toLength: 7, withPad: " ", startingAt: 0)
}

func render() {
    print("\u{1B}[2J\u{1B}[H", terminator: "")
    print("MetricsKit provider demo (Ctrl-C to quit)\n")

    if let cpu = store.latest(.cpu) {
        let history = store.history(.cpu, count: 40).map(\.normalized)
        let cores = Int(cpu.detail["coreCount"] ?? 0)
        print(
            "CPU     \(padded(MetricFormat.percent(cpu.value, decimals: 1))) "
                + "\(MetricFormat.sparkline(history))  [\(cores) cores]"
        )
    }

    if let memory = store.latest(.memory) {
        let history = store.history(.memory, count: 40).map(\.normalized)
        let used = memory.detail["used"] ?? 0
        let total = memory.detail["total"] ?? 0
        print(
            "Memory  \(padded(MetricFormat.percent(memory.value, decimals: 1))) "
                + "\(MetricFormat.sparkline(history))  "
                + "[\(MetricFormat.bytes(used)) / \(MetricFormat.bytes(total))]"
        )
    }

    if let battery = store.latest(.battery) {
        let charging = (battery.detail["charging"] ?? 0) > 0
            ? "charging"
            : "on battery"
        var extra = ""
        if let health = battery.detail["healthPercent"] {
            extra += "  health \(Int(health))%"
        }
        if let cycles = battery.detail["cycleCount"] {
            extra += "  cycles \(Int(cycles))"
        }
        if let temperature = battery.detail["temperature"] {
            extra += String(format: "  %.1f°C", temperature)
        }
        print(
            "Battery \(padded(MetricFormat.percent(battery.value))) "
                + "\(charging)\(extra)"
        )
    } else {
        print("Battery (no battery on this machine)")
    }

    if let network = store.latest(.network) {
        let down = network.detail["down"] ?? 0
        let up = network.detail["up"] ?? 0
        print(
            "Network ↓\(MetricFormat.compactRate(down))/s  "
                + "↑\(MetricFormat.compactRate(up))/s"
        )
    }

    if let disk = store.latest(.disk) {
        let used = disk.detail["used"] ?? 0
        let total = disk.detail["total"] ?? 0
        let readRate = disk.detail["readRate"] ?? 0
        let writeRate = disk.detail["writeRate"] ?? 0
        print(
            "Disk    \(padded(MetricFormat.percent(disk.value))) "
                + "[\(MetricFormat.bytes(used)) / \(MetricFormat.bytes(total))]  "
                + "R \(MetricFormat.compactRate(readRate))/s  "
                + "W \(MetricFormat.compactRate(writeRate))/s"
        )
    }

    if let gpu = store.latest(.gpu) {
        let history = store.history(.gpu, count: 40).map(\.normalized)
        print(
            "GPU     \(padded(MetricFormat.percent(gpu.value, decimals: 1))) "
                + MetricFormat.sparkline(history)
        )
    }

    if let temperature = store.latest(.sensors) {
        var extra = ""
        if let cpu = temperature.detail["cpuMax"] {
            extra += String(format: "  CPU %.1f°C", cpu)
        }
        if let gpu = temperature.detail["gpuMax"] {
            extra += String(format: "  GPU %.1f°C", gpu)
        }
        if let memory = temperature.detail["memoryMax"] {
            extra += String(format: "  Memory %.1f°C", memory)
        }
        print(
            "Temp    \(padded(String(format: "%.1f°C", temperature.value)))"
                + "\(extra)  "
                + "[\(Int(temperature.detail["sensorCount"] ?? 0)) sensors]"
        )
    }

    if let fans = store.latest(.fans) {
        let count = Int(fans.detail["fanCount"] ?? 0)
        print(
            "Fans    \(count) fan(s)  fastest "
                + "\(Int(fans.detail["maxRpm"] ?? 0)) RPM "
                + "(\(MetricFormat.percent(fans.value)))"
        )
    } else {
        print("Fans    (fanless machine)")
    }

    print("\nSampling: 1s · MetricsKit running ✓")
}

engine.onCycle = { _ in render() }
engine.start()
RunLoop.main.run()
