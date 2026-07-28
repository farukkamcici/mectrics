import Foundation

/// Public convenience surface of the package.
public enum MetricsKit {
    /// All implemented providers. Advanced modules (gpu/sensors/fans) come in later
    /// phases. Unavailable modules (e.g. no battery on a desktop, no BT device) are
    /// filtered out by the engine at registration time.
    public static func coreProviders() -> [MetricProvider] {
        [
            CPUProvider(),      // Phase 1
            MemoryProvider(),   // Phase 1
            BatteryProvider(),  // Phase 1
            NetworkProvider(),  // Phase 2
            DiskProvider(),     // Phase 2
            BluetoothProvider() // Phase 2
        ]
    }

    /// Builds an engine wired with the core providers, ready to start.
    public static func makeEngine(policy: SamplingPolicy = .default) -> MetricsEngine {
        let engine = MetricsEngine(policy: policy)
        engine.register(coreProviders())
        return engine
    }
}

/// Formatting helpers for presenting metrics to the user.
public enum MetricFormat {
    public static func percent(_ fraction: Double, decimals: Int = 0) -> String {
        String(format: "%.\(decimals)f%%", fraction * 100)
    }

    public static func bytes(_ value: Double) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var v = value
        var i = 0
        while v >= 1024 && i < units.count - 1 { v /= 1024; i += 1 }
        return String(format: "%.1f %@", v, units[i])
    }

    public static func bytesPerSecond(_ value: Double) -> String {
        bytes(value) + "/s"
    }

    /// Compact rate for the menu bar: 1.2M, 340K, 0. Single-letter unit.
    /// Uses a 1000 threshold so the mantissa never exceeds 999.9 — this keeps the
    /// menu-bar network item within its reserved (fixed) width.
    public static func compactRate(_ value: Double) -> String {
        let units = ["B", "K", "M", "G", "T"]
        var v = value
        var i = 0
        while v >= 1000 && i < units.count - 1 { v /= 1000; i += 1 }
        if i == 0 { return String(format: "%.0f", v) }
        return String(format: "%.1f%@", v, units[i])
    }

    /// ASCII sparkline — used by the CLI demo and tests.
    public static func sparkline(_ values: [Double]) -> String {
        guard !values.isEmpty else { return "" }
        let blocks = Array("▁▂▃▄▅▆▇█")
        let maxV = max(values.max() ?? 1, 0.0001)
        return String(values.map { v in
            let idx = Int((v / maxV) * Double(blocks.count - 1))
            return blocks[min(max(idx, 0), blocks.count - 1)]
        })
    }
}
