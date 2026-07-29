import Foundation
import MetricsKit

struct MenuBarLayoutEntry: Equatable {
    let metricID: MetricID
    let component: MenuBarComponent
}

struct MenuBarLayoutPreset: Identifiable, Equatable {
    let id: String
    let name: String
    let summary: String
    let entries: [MenuBarLayoutEntry]

    static let all: [MenuBarLayoutPreset] = [
        MenuBarLayoutPreset(
            id: "minimal",
            name: String(
                localized: "preset.minimal.name",
                defaultValue: "Minimal"
            ),
            summary: String(
                localized: "preset.minimal.summary",
                defaultValue: "Essential usage and battery at a glance"
            ),
            entries: [
                MenuBarLayoutEntry(metricID: .cpu, component: .value),
                MenuBarLayoutEntry(metricID: .memory, component: .value),
                MenuBarLayoutEntry(
                    metricID: .battery,
                    component: .batteryIcon
                )
            ]
        ),
        MenuBarLayoutPreset(
            id: "laptop",
            name: String(
                localized: "preset.laptop.name",
                defaultValue: "Laptop"
            ),
            summary: String(
                localized: "preset.laptop.summary",
                defaultValue: "Battery, workload, memory, and network"
            ),
            entries: [
                MenuBarLayoutEntry(metricID: .cpu, component: .valueGraph),
                MenuBarLayoutEntry(metricID: .memory, component: .value),
                MenuBarLayoutEntry(
                    metricID: .battery,
                    component: .batteryIcon
                ),
                MenuBarLayoutEntry(metricID: .battery, component: .value),
                MenuBarLayoutEntry(
                    metricID: .network,
                    component: .netActivity
                )
            ]
        ),
        MenuBarLayoutPreset(
            id: "developer",
            name: String(
                localized: "preset.developer.name",
                defaultValue: "Developer"
            ),
            summary: String(
                localized: "preset.developer.summary",
                defaultValue: "Detailed compute, memory, disk, and network activity"
            ),
            entries: [
                MenuBarLayoutEntry(metricID: .cpu, component: .valueGraph),
                MenuBarLayoutEntry(metricID: .cpu, component: .coreBars),
                MenuBarLayoutEntry(
                    metricID: .memory,
                    component: .valueGraph
                ),
                MenuBarLayoutEntry(
                    metricID: .network,
                    component: .netActivity
                ),
                MenuBarLayoutEntry(metricID: .disk, component: .freeBytes),
                MenuBarLayoutEntry(metricID: .gpu, component: .graph)
            ]
        )
    ]

    static func recommended(
        available: Set<MetricID>
    ) -> MenuBarLayoutPreset {
        let preferred: [MetricID] = [
            .cpu, .memory, .battery, .network
        ]
        return MenuBarLayoutPreset(
            id: "recommended",
            name: String(
                localized: "preset.recommended.name",
                defaultValue: "Recommended"
            ),
            summary: String(
                localized: "preset.recommended.summary",
                defaultValue: "The current product default for this Mac"
            ),
            entries: preferred.compactMap { id in
                guard available.contains(id) else { return nil }
                return MenuBarLayoutEntry(
                    metricID: id,
                    component: .default(for: id)
                )
            }
        )
    }

    func resolved(
        available: Set<MetricID>
    ) -> [MetricID: Set<MenuBarComponent>] {
        var result: [MetricID: Set<MenuBarComponent>] = [:]
        for entry in entries where available.contains(entry.metricID) {
            guard MenuBarComponent.available(
                for: entry.metricID
            ).contains(entry.component) else {
                continue
            }
            result[entry.metricID, default: []].insert(entry.component)
        }
        return result
    }
}
