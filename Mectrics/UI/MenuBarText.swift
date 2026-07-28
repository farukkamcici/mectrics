import Foundation
import MetricsKit

/// Modül başına menü çubuğu metnini ve sparkline gösterilip gösterilmeyeceğini üretir.
enum MenuBarText {
    static func showsSparkline(_ id: MetricID) -> Bool {
        switch id {
        case .cpu, .memory: return true
        default: return false
        }
    }

    static func string(for id: MetricID, sample: MetricSample) -> String {
        switch id {
        case .cpu:
            return MetricFormat.percent(sample.value, decimals: 0)
        case .memory:
            return MetricFormat.percent(sample.value, decimals: 0)
        case .battery:
            let pct = Int((sample.value * 100).rounded())
            let charging = (sample.detail["charging"] ?? 0) > 0
            return "\(charging ? "⚡" : "")\(pct)%"
        default:
            return MetricFormat.percent(sample.value, decimals: 0)
        }
    }
}
