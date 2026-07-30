import MetricsKit
import XCTest
@testable import Mectrics

final class MenuBarLayoutPresetTests: XCTestCase {
    func testExactlyThreeDeterministicPresetsUseValidComponents() {
        XCTAssertEqual(
            MenuBarLayoutPreset.all.map(\.id),
            ["essentials", "recommended", "detailed"]
        )
        for preset in MenuBarLayoutPreset.all {
            for entry in preset.entries {
                XCTAssertTrue(
                    MenuBarComponent.available(
                        for: entry.metricID
                    ).contains(entry.component)
                )
                let template = entry.component.template(
                    for: entry.metricID
                )
                XCTAssertFalse(
                    template.contains("\n\n"),
                    "Stable-width templates must remain bounded"
                )
            }
        }
    }

    func testHardwareUsageModulesOfferIndependentTemperatureItems() {
        for id in [MetricID.cpu, .memory, .gpu] {
            XCTAssertTrue(
                MenuBarComponent.available(for: id).contains(.temperature)
            )
            XCTAssertEqual(
                MenuBarComponent.temperature.template(for: id),
                "125°"
            )
        }

        let sample = MetricSample(value: 0.5)
        guard case .text(let text) = MenuBarText.visual(
            for: .cpu,
            component: .temperature,
            sample: sample,
            temperature: 63.6
        ) else {
            return XCTFail("Temperature must render as text")
        }
        XCTAssertEqual(text, "64°")
    }

    /// The presets vary along one axis, so each has to contain the one before it.
    func testPresetsAreOrderedByDensity() {
        let all: Set<MetricID> = [
            .cpu, .memory, .battery, .network, .disk, .gpu
        ]
        XCTAssertEqual(
            MenuBarLayoutPreset.all.map { $0.itemCount(available: all) },
            [3, 4, 5]
        )

        let recommended = MenuBarLayoutPreset.recommended
            .resolved(available: all)
        let detailed = try! XCTUnwrap(
            MenuBarLayoutPreset.all.first { $0.id == "detailed" }
        ).resolved(available: all)
        for (id, components) in recommended {
            XCTAssertTrue(
                components.isSubset(of: detailed[id] ?? []),
                "Detailed must build on Recommended"
            )
        }
    }

    func testItemCountReflectsThisMacRatherThanTheDeclaredEntries() {
        let desktop: Set<MetricID> = [.cpu, .memory, .network, .disk]
        XCTAssertEqual(
            MenuBarLayoutPreset.recommended.itemCount(available: desktop),
            3
        )
        XCTAssertEqual(
            MenuBarLayoutPreset.all[0].itemCount(available: desktop),
            2
        )
    }

    func testUnsupportedModulesAreOmittedWithoutBrokenEntries() {
        let desktop: Set<MetricID> = [
            .cpu, .memory, .disk, .network
        ]
        let detailed = try! XCTUnwrap(
            MenuBarLayoutPreset.all.first { $0.id == "detailed" }
        )
        let resolved = detailed.resolved(available: desktop)

        XCTAssertNil(resolved[.battery])
        XCTAssertNil(resolved[.gpu])
        XCTAssertNotNil(resolved[.cpu])
        XCTAssertNotNil(resolved[.memory])
        XCTAssertNotNil(resolved[.disk])
        XCTAssertNotNil(resolved[.network])
    }

    func testRecommendedAdaptsToLaptopDesktopFanlessAndNoGPU() {
        let laptop: Set<MetricID> = [
            .cpu, .memory, .battery, .network, .disk, .gpu
        ]
        let desktop: Set<MetricID> = [
            .cpu, .memory, .network, .disk, .fans
        ]
        let fanless: Set<MetricID> = [
            .cpu, .memory, .battery, .network, .disk
        ]
        let noGPU: Set<MetricID> = [
            .cpu, .memory, .battery, .network
        ]
        let recommended = MenuBarLayoutPreset.recommended

        XCTAssertEqual(
            Set(recommended.resolved(available: laptop).keys),
            [.cpu, .memory, .battery, .network]
        )
        XCTAssertEqual(
            Set(recommended.resolved(available: desktop).keys),
            [.cpu, .memory, .network]
        )
        XCTAssertEqual(
            Set(recommended.resolved(available: fanless).keys),
            [.cpu, .memory, .battery, .network]
        )
        XCTAssertEqual(
            Set(recommended.resolved(available: noGPU).keys),
            [.cpu, .memory, .battery, .network]
        )
    }

    func testPresetReplacementLeavesCompletePriorLayoutAvailableForUndo() {
        let prior: [MetricID: Set<MenuBarComponent>] = [
            .cpu: [.coreBars, .value],
            .disk: [.ring]
        ]
        let preset = MenuBarLayoutPreset.all[0]
        let replacement = preset.resolved(
            available: [.cpu, .memory, .battery, .disk]
        )

        XCTAssertNotEqual(replacement, prior)
        XCTAssertEqual(
            prior,
            [
                .cpu: [.coreBars, .value],
                .disk: [.ring]
            ]
        )
    }
}
