import MetricsKit
import XCTest
@testable import Mectrics

final class MenuBarLayoutPresetTests: XCTestCase {
    func testExactlyThreeDeterministicPresetsUseValidComponents() {
        XCTAssertEqual(
            MenuBarLayoutPreset.all.map(\.id),
            ["minimal", "laptop", "developer"]
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

    func testUnsupportedModulesAreOmittedWithoutBrokenEntries() {
        let desktop: Set<MetricID> = [
            .cpu, .memory, .disk, .network
        ]
        let developer = try! XCTUnwrap(
            MenuBarLayoutPreset.all.first { $0.id == "developer" }
        )
        let resolved = developer.resolved(available: desktop)

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

        XCTAssertEqual(
            Set(MenuBarLayoutPreset.recommended(
                available: laptop
            ).resolved(available: laptop).keys),
            [.cpu, .memory, .battery, .network]
        )
        XCTAssertEqual(
            Set(MenuBarLayoutPreset.recommended(
                available: desktop
            ).resolved(available: desktop).keys),
            [.cpu, .memory, .network]
        )
        XCTAssertEqual(
            Set(MenuBarLayoutPreset.recommended(
                available: fanless
            ).resolved(available: fanless).keys),
            [.cpu, .memory, .battery, .network]
        )
        XCTAssertEqual(
            Set(MenuBarLayoutPreset.recommended(
                available: noGPU
            ).resolved(available: noGPU).keys),
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
