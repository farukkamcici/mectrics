import Foundation
import MetricsKit

struct MenuBarLayoutEntry: Equatable {
    let metricID: MetricID
    let component: MenuBarComponent
}

/// A ready-made menu bar layout.
///
/// The three presets vary along one axis — how much detail you want — and each is a
/// superset or subset of the next, so moving between them is predictable. Earlier
/// presets mixed axes (density, hardware, profession) and asked the user to place
/// themselves on three different scales at once.
struct MenuBarLayoutPreset: Identifiable, Equatable {
    let id: String
    let name: String
    let entries: [MenuBarLayoutEntry]

    static let all: [MenuBarLayoutPreset] = [
        MenuBarLayoutPreset(
            id: "essentials",
            name: String(
                localized: "preset.essentials.name",
                defaultValue: "Essentials"
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
            id: "recommended",
            name: String(
                localized: "preset.recommended.name",
                defaultValue: "Recommended"
            ),
            entries: recommendedEntries
        ),
        MenuBarLayoutPreset(
            id: "detailed",
            name: String(
                localized: "preset.detailed.name",
                defaultValue: "Detailed"
            ),
            // Recommended plus free disk space. GPU is left out on purpose: it idles
            // near zero for most people, so a permanent item earns little.
            entries: recommendedEntries + [
                MenuBarLayoutEntry(metricID: .disk, component: .freeBytes)
            ]
        )
    ]

    private static let recommendedEntries: [MenuBarLayoutEntry] = [
        MenuBarLayoutEntry(metricID: .cpu, component: .valueGraph),
        MenuBarLayoutEntry(metricID: .memory, component: .valueGraph),
        MenuBarLayoutEntry(metricID: .battery, component: .value),
        MenuBarLayoutEntry(metricID: .network, component: .netActivity)
    ]

    static var recommended: MenuBarLayoutPreset {
        all.first { $0.id == "recommended" } ?? all[0]
    }

    /// How many menu bar items this preset actually adds on this Mac — a desktop drops
    /// the battery entries, so the count has to be resolved rather than declared.
    func itemCount(available: Set<MetricID>) -> Int {
        resolved(available: available).values.reduce(0) { $0 + $1.count }
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
