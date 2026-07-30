import Foundation

/// Temperature sensors via the SMC.
///
/// Key names differ per chip generation (Intel: `TC0P` …; Apple Silicon: `Tp??` CPU
/// cluster, `Tg??` GPU, and many more), so instead of a hardcoded list we enumerate
/// every `T…` key once and keep those that decode to a plausible temperature
/// (1...125 °C). `value` = hottest CPU-cluster temperature in °C (`.celsius` unit —
/// not normalized). Detail: `cpuMax`, `gpuMax`, `memoryMax` (when present) and
/// `sensorCount`.
public final class SensorsProvider: MetricProvider, @unchecked Sendable {
    public let id: MetricID = .sensors
    public let cost: SamplingCost = .heavy

    private let smc: SMCClient?
    /// Discovered once at init: plausible temperature keys, split by prefix class.
    /// `otherKeys` holds the remainder, so a sample never reads the same key twice.
    private let cpuKeys: [String]
    private let gpuKeys: [String]
    private let memoryKeys: [String]
    private let otherKeys: [String]
    private let sensorCount: Int

    public init() {
        self.smc = SMCClient()
        guard let smc else {
            cpuKeys = []; gpuKeys = []; memoryKeys = []; otherKeys = []
            sensorCount = 0
            return
        }

        var cpu: [String] = [], gpu: [String] = [], memory: [String] = []
        var other: [String] = []
        var count = 0
        for name in smc.allKeyNames() where name.hasPrefix("T") {
            guard let value = smc.readValue(name), (1...125).contains(value) else { continue }
            count += 1
            // Apple Silicon: Tp = P-cores, Te = E-cores; Intel: TC = CPU. Tg/TG = GPU.
            if name.hasPrefix("Tp") || name.hasPrefix("Te") || name.hasPrefix("TC") {
                cpu.append(name)
            } else if name.hasPrefix("Tg") || name.hasPrefix("TG") {
                gpu.append(name)
            } else if Self.isMemoryTemperatureKey(name) {
                memory.append(name)
            } else {
                other.append(name)
            }
        }
        cpuKeys = cpu
        gpuKeys = gpu
        memoryKeys = memory
        otherKeys = other
        sensorCount = count
    }

    public var isAvailable: Bool { smc != nil && sensorCount > 0 }

    public func sample() -> MetricSample? {
        guard let smc, sensorCount > 0 else { return nil }

        func maxTemp(_ keys: [String]) -> Double? {
            var result: Double?
            for key in keys {
                guard let value = smc.readValue(key), (1...125).contains(value) else { continue }
                result = max(result ?? value, value)
            }
            return result
        }

        let cpuMax = maxTemp(cpuKeys)
        let gpuMax = maxTemp(gpuKeys)
        let memoryMax = maxTemp(memoryKeys)
        // Without a CPU-cluster sensor, the hottest key of any class stands in. Only
        // the keys not already read above are visited.
        guard let hottest = cpuMax
            ?? [gpuMax, memoryMax, maxTemp(otherKeys)].compactMap({ $0 }).max()
        else { return nil }

        var detail: [String: Double] = ["sensorCount": Double(sensorCount)]
        if let cpuMax { detail["cpuMax"] = cpuMax }
        if let gpuMax { detail["gpuMax"] = gpuMax }
        if let memoryMax { detail["memoryMax"] = memoryMax }
        return MetricSample(value: hottest, unit: .celsius, detail: detail)
    }

    /// Intel memory sensors use the uppercase `TM` family. Apple Silicon uses a
    /// small set of lowercase `Tm` keys; keep those explicit because `Tm0P` is a
    /// mainboard sensor on some Intel Macs and must not be presented as RAM.
    static func isMemoryTemperatureKey(_ key: String) -> Bool {
        if key.hasPrefix("TM") { return true }
        return [
            "Tm02", "Tm06", "Tm08", "Tm09",
            "Tm0p", "Tm1p", "Tm2p"
        ].contains(key)
    }
}
