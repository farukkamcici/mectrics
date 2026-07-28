import Foundation

/// Paketin kamuya açık kolaylık yüzeyi.
public enum MetricsKit {
    /// Uygulanmış tüm provider'lar. İleri modüller (gpu/sensör/fan) sonraki fazlarda.
    /// Kullanılamayan modüller (ör. pilsiz masaüstü, BT cihazı yok) engine tarafından elenir.
    public static func coreProviders() -> [MetricProvider] {
        [
            CPUProvider(),      // Faz 1
            MemoryProvider(),   // Faz 1
            BatteryProvider(),  // Faz 1
            NetworkProvider(),  // Faz 2
            DiskProvider(),     // Faz 2
            BluetoothProvider() // Faz 2
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

    /// Menü çubuğu için kompakt hız: 1.2M, 340K, 0. (Birim harfi tek karakter.)
    public static func compactRate(_ value: Double) -> String {
        let units = ["B", "K", "M", "G", "T"]
        var v = value
        var i = 0
        while v >= 1024 && i < units.count - 1 { v /= 1024; i += 1 }
        if i == 0 { return String(format: "%.0f", v) }
        return String(format: "%.1f%@", v, units[i])
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
