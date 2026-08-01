import Foundation

protocol SMCValueReading: AnyObject {
    func readValue(_ name: String) -> Double?
}

extension SMCClient: SMCValueReading {}

/// Fan speeds via the SMC (`FNum`, `F0Ac` actual RPM, `F0Mx` max RPM).
///
/// Fanless machines (MacBook Air) report no fans and the module hides itself.
/// `value` = highest actual/max ratio across fans (0...1); detail: `fanCount`,
/// `fan<i>Rpm`, `fan<i>MaxRpm` and `maxRpm` (the fastest fan's current RPM).
public final class FansProvider: MetricProvider, @unchecked Sendable {
    public let id: MetricID = .fans
    public let cost: SamplingCost = .heavy

    private let smc: (any SMCValueReading)?
    private let fanIndices: [Int]

    public convenience init() {
        self.init(smc: SMCClient())
    }

    init(smc: (any SMCValueReading)?) {
        self.smc = smc
        fanIndices = Self.detectFanIndices(using: smc)
    }

    public var isAvailable: Bool { smc != nil && !fanIndices.isEmpty }

    public func sample() -> MetricSample? {
        guard let smc, !fanIndices.isEmpty else { return nil }

        var detail: [String: Double] = [
            "fanCount": Double(fanIndices.count)
        ]
        var maxRatio = 0.0
        var maxRpm = 0.0
        var gotAny = false

        for i in fanIndices {
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

    private static func detectFanIndices(
        using smc: (any SMCValueReading)?
    ) -> [Int] {
        guard let smc else { return [] }
        if let rawCount = smc.readValue("FNum"), rawCount.isFinite {
            let count = Int(rawCount)
            if count == 0 { return [] }
            if (1...8).contains(count) { return Array(0..<count) }
        }

        // Some SMC implementations expose current fan speeds even when the count
        // key cannot be read. Probe the read-only speed keys once so a real fan is
        // not hidden solely because FNum is missing or malformed.
        return (0..<8).filter { smc.readValue("F\($0)Ac") != nil }
    }
}
