import Foundation
import MetricsKit

/// One selectable menu bar component. Each module offers a subset (see
/// `available(for:)`), and the user can enable several components for a module.
enum MenuBarComponent: String, CaseIterable, Identifiable {
    // Generic
    case value, graph, valueGraph
    // CPU
    case coreBars
    // Capacity texts (memory used, disk used/free)
    case usedBytes, freeBytes
    // Disk pictorial
    case ring
    // Battery
    case batteryIcon, health, cycles
    // Network
    case netActivity, netDown, netUp

    var id: String { rawValue }

    static func available(for module: MetricID) -> [MenuBarComponent] {
        switch module {
        case .cpu:       return [.value, .graph, .valueGraph, .coreBars]
        case .memory:    return [.value, .graph, .valueGraph, .usedBytes]
        case .gpu:       return [.value, .graph, .valueGraph]
        case .battery:   return [.value, .batteryIcon, .health, .cycles]
        case .disk:      return [.value, .ring, .usedBytes, .freeBytes]
        case .network:   return [.netActivity, .netDown, .netUp]
        default:         return [.value]
        }
    }

    static func `default`(for module: MetricID) -> MenuBarComponent {
        switch module {
        case .cpu, .memory, .gpu: return .valueGraph
        case .network:            return .netActivity
        default:                  return .value
        }
    }

    var localizedName: String {
        switch self {
        case .value:       return String(localized: "component.value", defaultValue: "Value")
        case .graph:       return String(localized: "component.graph", defaultValue: "Graph")
        case .valueGraph:  return String(localized: "component.valueGraph", defaultValue: "Value + Graph")
        case .coreBars:    return String(localized: "component.coreBars", defaultValue: "Cores")
        case .usedBytes:   return String(localized: "component.used", defaultValue: "Used")
        case .freeBytes:   return String(localized: "component.free", defaultValue: "Free")
        case .ring:        return String(localized: "component.ring", defaultValue: "Ring")
        case .batteryIcon: return String(localized: "component.icon", defaultValue: "Icon")
        case .health:      return String(localized: "component.health", defaultValue: "Health")
        case .cycles:      return String(localized: "component.cycles", defaultValue: "Cycles")
        case .netActivity: return String(localized: "component.activity", defaultValue: "Activity")
        case .netDown:     return String(localized: "component.download", defaultValue: "Download")
        case .netUp:       return String(localized: "component.upload", defaultValue: "Upload")
        }
    }

    /// Worst-case template reserving a stable text slot ("" = pictorial, no text).
    /// Real values must never exceed this width.
    func template(for module: MetricID) -> String {
        switch self {
        case .graph, .coreBars, .ring, .batteryIcon:
            return ""
        case .usedBytes, .freeBytes:
            return "999GB"
        case .health:
            return "100%"
        case .cycles:
            return "9999"
        case .netActivity, .netDown, .netUp:
            return "↓999M"
        case .value, .valueGraph:
            switch module {
            // The charging bolt is part of the value, so it belongs in the template.
            case .battery:   return "⚡100%"
            case .bluetooth: return "BT 100%"
            case .fans:      return "9.9K"
            default:         return "100%"
            }
        }
    }
}

/// What the status item should actually draw this cycle — resolved from
/// (module, component, latest sample) by `MenuBarText.visual`.
enum MenuBarVisual {
    case text(String)                          // right-aligned text (may be two-line)
    case textGraph(String)                     // text + sparkline
    case graph                                 // sparkline only
    case coreBars([Double])                    // one mini bar per CPU core
    case battery(level: Double, charging: Bool)
    case ring(Double)                          // fraction donut
}

extension MenuBarText {
    static func visual(for id: MetricID, component: MenuBarComponent,
                       sample: MetricSample) -> MenuBarVisual {
        switch component {
        case .value:
            return .text(string(for: id, sample: sample))
        case .graph:
            return .graph
        case .valueGraph:
            return .textGraph(string(for: id, sample: sample))
        case .coreBars:
            let cores = Int(sample.detail["coreCount"] ?? 0)
            return .coreBars((0..<cores).compactMap { sample.detail["core\($0)"] })
        case .usedBytes:
            return .text(MetricFormat.menuRate(sample.detail["used"] ?? 0) + "B")
        case .freeBytes:
            return .text(MetricFormat.menuRate(sample.detail["free"] ?? 0) + "B")
        case .ring:
            return .ring(sample.value)
        case .batteryIcon:
            return .battery(level: sample.value,
                            charging: (sample.detail["charging"] ?? 0) > 0)
        // A missing reading is absence, not zero: never render 0% health or 0 cycles
        // for a battery that simply did not report them.
        case .health:
            guard let health = sample.detail["healthPercent"] else {
                return .text("—")
            }
            return .text("\(Int(health))%")
        case .cycles:
            guard let cycles = sample.detail["cycleCount"] else {
                return .text("—")
            }
            return .text("\(Int(cycles))")
        case .netActivity:
            return .text(string(for: .network, sample: sample))
        case .netDown:
            return .text("↓\(MetricFormat.menuRate(sample.detail["down"] ?? 0))")
        case .netUp:
            return .text("↑\(MetricFormat.menuRate(sample.detail["up"] ?? 0))")
        }
    }
}
