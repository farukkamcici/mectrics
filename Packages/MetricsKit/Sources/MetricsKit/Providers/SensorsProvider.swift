import Foundation

/// Temperature sensors via the SMC.
///
/// Key names differ per chip generation (Intel: `TC0P` …; Apple Silicon: `Tp??` CPU
/// cluster, `Tg??` GPU, and many more), so instead of a hardcoded list we enumerate
/// every `T…` key once and keep those that decode to a plausible temperature
/// (1...125 °C). `value` = hottest CPU-cluster temperature in °C (`.celsius` unit —
/// not normalized). Detail: `cpuMax`, `gpuMax` (when present) and `sensorCount`.
public final class SensorsProvider: MetricProvider, @unchecked Sendable {
    public let id: MetricID = .sensors
    public let cost: SamplingCost = .heavy

    private let smc: SMCClient?
    /// Discovered once at init: plausible temperature keys, split by prefix class.
    private let cpuKeys: [String]
    private let gpuKeys: [String]
    private let allKeys: [String]

    public init() {
        self.smc = SMCClient()
        guard let smc else {
            cpuKeys = []; gpuKeys = []; allKeys = []
            return
        }

        var cpu: [String] = [], gpu: [String] = [], all: [String] = []
        for name in smc.allKeyNames() where name.hasPrefix("T") {
            guard let value = smc.readValue(name), (1...125).contains(value) else { continue }
            all.append(name)
            // Apple Silicon: Tp = P-cores, Te = E-cores; Intel: TC = CPU. Tg/TG = GPU.
            if name.hasPrefix("Tp") || name.hasPrefix("Te") || name.hasPrefix("TC") {
                cpu.append(name)
            } else if name.hasPrefix("Tg") || name.hasPrefix("TG") {
                gpu.append(name)
            }
        }
        cpuKeys = cpu
        gpuKeys = gpu
        allKeys = all
    }

    public var isAvailable: Bool { smc != nil && !allKeys.isEmpty }

    public func sample() -> MetricSample? {
        guard let smc, !allKeys.isEmpty else { return nil }

        func maxTemp(_ keys: [String]) -> Double? {
            let values = keys.compactMap { smc.readValue($0) }.filter { (1...125).contains($0) }
            return values.max()
        }

        let cpuMax = maxTemp(cpuKeys)
        let gpuMax = maxTemp(gpuKeys)
        guard let hottest = cpuMax ?? maxTemp(allKeys) else { return nil }

        var detail: [String: Double] = ["sensorCount": Double(allKeys.count)]
        if let cpuMax { detail["cpuMax"] = cpuMax }
        if let gpuMax { detail["gpuMax"] = gpuMax }
        return MetricSample(value: hottest, unit: .celsius, detail: detail)
    }
}
