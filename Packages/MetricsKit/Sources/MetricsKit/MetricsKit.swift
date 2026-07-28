import Foundation

/// Paketin kamuya açık kolaylık yüzeyi.
public enum MetricsKit {
    /// v0.1 (MVP) çekirdek provider'ları. İleri modüller (network/disk/gpu/sensör/fan)
    /// sonraki fazlarda eklenecek.
    public static func coreProviders() -> [MetricProvider] {
        [
            CPUProvider(),
            MemoryProvider(),
            BatteryProvider()
        ]
    }

    /// Çekirdek provider'larla kurulmuş, başlamaya hazır bir motor üretir.
    public static func makeEngine(policy: SamplingPolicy = .default) -> MetricsEngine {
        let engine = MetricsEngine(policy: policy)
        engine.register(coreProviders())
        return engine
    }
}

/// Metrikleri kullanıcıya gösterirken kullanılacak biçimlendiriciler.
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

    /// ASCII sparkline — CLI demosu ve testler için.
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
