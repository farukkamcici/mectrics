import Foundation

/// Public convenience surface of the package.
public enum MetricsKit {
    /// All implemented providers. Unavailable modules (e.g. no battery on a desktop,
    /// no fans on a fanless machine) are filtered out by the engine at registration
    /// time.
    public static func coreProviders() -> [MetricProvider] {
        [
            CPUProvider(),       // Phase 1
            MemoryProvider(),    // Phase 1
            BatteryProvider(),   // Phase 1
            NetworkProvider(),   // Phase 2
            DiskProvider(),      // Phase 2
            GPUProvider(),       // Phase 3
            SensorsProvider(),   // Phase 3
            FansProvider()       // Phase 3
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

    /// Ultra-compact rate for the (narrow, stacked) menu-bar network item.
    ///
    /// Always ≤ 4 glyphs including the single-letter unit — e.g. `0`, `1.2K`, `35K`,
    /// `999K`, `9.9M`, `120M`, `1.2G`. The value is scaled at 1000 so the mantissa is
    /// always < 1000, and sub-KB/s traffic collapses to `0`. The widest output
    /// (`999K` / `9.9M`) bounds the reserved slot, keeping the item width stable.
    public static func menuRate(_ value: Double) -> String {
        guard value >= 1000 else { return "0" }
        let units = ["K", "M", "G", "T"]
        var v = value / 1000
        var i = 0
        // Scale at 999.5 (not 1000) so "%.0f" rounding can never produce "1000K".
        while v >= 999.5 && i < units.count - 1 { v /= 1000; i += 1 }
        // Past the largest unit there is nothing left to divide by, so without this the
        // mantissa would keep growing and the output would outgrow its reserved menu bar
        // slot. Holding it at the ceiling is what makes the "≤ 4 glyphs" promise above
        // provable for every input rather than merely true for the ones we expect.
        v = min(v, 999)
        // Mantissa is now in 1...999.
        if v >= 10 { return String(format: "%.0f%@", v, units[i]) }   // 10–999 → "35K", "999K"
        return String(format: "%.1f%@", v, units[i])                  // 1.0–9.9 → "1.2K", "9.9M"
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
