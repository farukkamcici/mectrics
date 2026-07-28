import Foundation
import MetricsKit

/// Produces the per-module menu bar string and whether to show a sparkline.
///
/// Menu bar strings are numeric/symbolic (not natural language) so they are not
/// localized; user-facing prose lives in the popover/settings via String Catalog.
enum MenuBarText {
    static func showsSparkline(_ id: MetricID) -> Bool {
        switch id {
        case .cpu, .memory, .gpu: return true
        default: return false
        }
    }

    /// Menu bar strings drop the "%" glyph entirely — every percent item is a bare
    /// number ("75"), which keeps items as narrow as possible. Full labeled values
    /// live in the popover.
    static func string(for id: MetricID, sample: MetricSample) -> String {
        switch id {
        case .cpu, .memory:
            return bareNumber(sample.value)
        case .battery:
            let charging = (sample.detail["charging"] ?? 0) > 0
            return "\(charging ? "⚡" : "")\(bareNumber(sample.value))"
        case .network:
            // Stacked two lines (down over up) so the item stays narrow. The renderer
            // splits on the newline and draws each line right-aligned in a small font.
            let down = sample.detail["down"] ?? 0
            let up = sample.detail["up"] ?? 0
            return "↓\(MetricFormat.menuRate(down))\n↑\(MetricFormat.menuRate(up))"
        case .disk:
            return bareNumber(sample.value)
        case .bluetooth:
            return "BT\(bareNumber(sample.value))"
        case .sensors:
            // value is °C (not normalized); show the hottest CPU-cluster temp.
            return "\(Int(sample.value.rounded()))°"
        case .fans:
            // Show the fastest fan's RPM compactly (e.g. "2.4K").
            return MetricFormat.menuRate(sample.detail["maxRpm"] ?? 0)
        default:
            return bareNumber(sample.value)
        }
    }

    /// 0...1 fraction → "75" (no % sign).
    private static func bareNumber(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))"
    }
}
