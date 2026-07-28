import Foundation

/// Fan speeds via the SMC (`FNum`, `F0Ac` actual RPM, `F0Mx` max RPM).
///
/// Fanless machines (MacBook Air) report no fans and the module hides itself.
/// `value` = highest actual/max ratio across fans (0...1); detail: `fanCount`,
/// `fan<i>Rpm`, `fan<i>MaxRpm` and `maxRpm` (the fastest fan's current RPM).
public final class FansProvider: MetricProvider, @unchecked Sendable {
    public let id: MetricID = .fans
    public let cost: SamplingCost = .heavy

    private let smc: SMCClient?
    private let fanCount: Int

    public init() {
        self.smc = SMCClient()
        let count = smc?.readValue("FNum").map(Int.init) ?? 0
        self.fanCount = (0...8).contains(count) ? count : 0
    }

    public var isAvailable: Bool { smc != nil && fanCount > 0 }

    public func sample() -> MetricSample? {
        guard let smc, fanCount > 0 else { return nil }

        var detail: [String: Double] = ["fanCount": Double(fanCount)]
        var maxRatio = 0.0
        var maxRpm = 0.0
        var gotAny = false

        for i in 0..<fanCount {
            guard let actual = smc.readValue("F\(i)Ac"), actual >= 0 else { continue }
            gotAny = true
            detail["fan\(i)Rpm"] = actual
            maxRpm = max(maxRpm, actual)
            if let limit = smc.readValue("F\(i)Mx"), limit > 0 {
                detail["fan\(i)MaxRpm"] = limit
                maxRatio = max(maxRatio, min(actual / limit, 1))
            }
        }
        guard gotAny else { return nil }

        detail["maxRpm"] = maxRpm
        return MetricSample(value: maxRatio, unit: .fraction, detail: detail)
    }
}
