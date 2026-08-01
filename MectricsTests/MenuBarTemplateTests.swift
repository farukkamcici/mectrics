import AppKit
import XCTest
import MetricsKit
@testable import Mectrics

/// Width stability is the menu bar's one hard rule: an item reserves a fixed slot from
/// a worst-case template and right-aligns inside it, so a value gaining a digit must
/// never push its neighbours sideways.
///
/// The rule used to be enforced only by an `assert` at draw time, which means a Debug
/// build crashes on a Mac in the wrong state and a Release build silently draws outside
/// its slot. These tests check the same property up front, against the real formatters
/// and the real font, for every component a module can show.
final class MenuBarTemplateTests: XCTestCase {

    /// Values chosen to exercise each formatter's digit-count and unit-letter
    /// boundaries — the places a template is most likely to be too narrow.
    private static let fractions: [Double] = [
        0, 0.005, 0.09, 0.1, 0.5, 0.909, 0.999, 1
    ]

    private static let byteCounts: [Double] = [
        0, 999, 1_000, 99_999, 999_000,
        1_000_000, 120_000_000, 999_000_000,          // the wide "999MB" band
        1_000_000_000, 120_000_000_000, 999_000_000_000,
        1_000_000_000_000, 99_000_000_000_000, 8_000_000_000_000_000
    ]

    private func width(_ text: String, _ font: NSFont) -> CGFloat {
        text.components(separatedBy: "\n")
            .map { ceil(($0 as NSString).size(withAttributes: [.font: font]).width) }
            .max() ?? 0
    }

    /// Every text a component can render must fit the slot its template reserved.
    func testEveryComponentFitsItsReservedWidth() {
        for module in MetricID.allCases {
            for component in MenuBarComponent.available(for: module) {
                let font = MetricStatusItem.font(for: component)
                let reserved = MetricStatusItem.reservedTextWidth(
                    for: component,
                    module: module
                )

                for sample in Self.samples(for: module) {
                    let visual = MenuBarText.visual(
                        for: module,
                        component: component,
                        sample: sample,
                        temperature: sample.detail["cpuMax"]
                    )
                    guard let text = Self.text(of: visual) else { continue }

                    XCTAssertLessThanOrEqual(
                        width(text, font),
                        reserved,
                        """
                        \(module.rawValue).\(component.rawValue) rendered "\(text)", \
                        which is wider than the "\(component.template(for: module))" \
                        slot it reserved. Widen the template — digits are monospaced \
                        but unit letters are not.
                        """
                    )
                }
            }
        }
    }

    /// A missing reading renders a dash, and a dash must fit too — otherwise the
    /// absence-is-not-zero rule would trade one bug for another.
    func testMissingReadingsStillFitTheirSlot() {
        let empty = MetricSample(value: 0, unit: .fraction, detail: [:])

        for module in MetricID.allCases {
            for component in MenuBarComponent.available(for: module) {
                let visual = MenuBarText.visual(
                    for: module,
                    component: component,
                    sample: empty,
                    temperature: nil
                )
                guard let text = Self.text(of: visual) else { continue }

                XCTAssertLessThanOrEqual(
                    width(text, MetricStatusItem.font(for: component)),
                    MetricStatusItem.reservedTextWidth(
                        for: component,
                        module: module
                    ),
                    "\(module.rawValue).\(component.rawValue) overflows on \"\(text)\""
                )
            }
        }
    }

    // MARK: - Fixtures

    private static func text(of visual: MenuBarVisual) -> String? {
        switch visual {
        case .text(let text), .textGraph(let text):
            return text
        // Pictorial components have inherently fixed sizes and reserve no text slot.
        case .coreBars, .battery, .ring:
            return nil
        }
    }

    private static func samples(for module: MetricID) -> [MetricSample] {
        switch module {
        case .battery:
            return fractions.flatMap { level in
                [false, true].map { charging in
                    MetricSample(
                        value: level,
                        unit: .fraction,
                        detail: [
                            "charging": charging ? 1 : 0,
                            // A replacement battery can measure above its design
                            // capacity, so health is not capped at 100.
                            "healthPercent": 104,
                            "cycleCount": 9_999
                        ]
                    )
                }
            }
        case .network:
            return byteCounts.map { rate in
                MetricSample(
                    value: rate,
                    unit: .bytesPerSecond,
                    detail: ["down": rate, "up": rate]
                )
            }
        case .disk, .memory:
            return byteCounts.flatMap { bytes in
                fractions.map { fraction in
                    MetricSample(
                        value: fraction,
                        unit: .fraction,
                        detail: [
                            "used": bytes,
                            "free": bytes,
                            "total": bytes,
                            "cpuMax": 125
                        ]
                    )
                }
            }
        case .fans:
            // `FansProvider` rejects anything outside its plausible range, so the
            // ceiling of that range is the widest a fan item can ever render.
            return [0, 1_200, 6_000, FansProvider.plausibleRPM.upperBound].map { rpm in
                MetricSample(
                    value: 1,
                    unit: .fraction,
                    detail: ["maxRpm": rpm, "fanCount": 1]
                )
            }
        case .cpu:
            return fractions.map { fraction in
                MetricSample(
                    value: fraction,
                    unit: .fraction,
                    detail: [
                        "coreCount": 24,
                        // Temperatures are validated to 1...125 °C by SensorsProvider.
                        "cpuMax": 125
                    ]
                )
            }
        case .gpu, .sensors:
            return fractions.map { fraction in
                MetricSample(
                    value: fraction,
                    unit: .fraction,
                    detail: ["cpuMax": 125]
                )
            }
        }
    }
}
