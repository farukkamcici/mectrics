import MetricsKit
import XCTest
@testable import Mectrics

final class SystemSummaryTests: XCTestCase {
    func testExactAllowlistedSummarySchemaAndMissingReadingState() {
        let input = SystemSummaryInput(
            appVersion: "1.2.3",
            appBuild: "42",
            operatingSystem: "macOS 15.6",
            architecture: "arm64",
            modelFamily: "Portable Mac",
            metrics: [
                SystemSummaryMetric(
                    id: .cpu,
                    state: .live,
                    reading: "42.0%"
                ),
                SystemSummaryMetric(
                    id: .battery,
                    state: .unavailable,
                    reading: nil
                )
            ],
            conditions: [
                SystemSummaryCondition(
                    conditionKey: "threshold.cpu",
                    metricID: .cpu,
                    state: .active,
                    severity: .warning
                )
            ],
            energyGuardMode: .reduced
        )

        XCTAssertEqual(
            SystemSummaryBuilder.render(
                input,
                locale: Locale(identifier: "en")
            ),
            """
            Mectrics System Summary
            Schema: mectrics.system-summary.v1
            App: 1.2.3 (42)
            macOS: macOS 15.6
            Architecture: arm64
            Mac family: Portable Mac
            Energy Guard: reduced

            Metrics:
            - cpu | state=live | reading=42.0%
            - battery | state=unavailable

            Active conditions:
            - threshold.cpu | metric=cpu | state=active | severity=warning

            """
        )
    }

    func testSummaryCannotContainNonAllowlistedPrivateFixtureFields() {
        let privateFixture = [
            "alice",
            "alice-mac.local",
            "Safari",
            "C02PRIVATE",
            "aa:bb:cc:dd:ee:ff",
            "192.168.1.10",
            "Home Wi-Fi",
            "Alice AirPods",
            "/Users/alice/Documents"
        ]
        let input = SystemSummaryInput(
            appVersion: "1.0",
            appBuild: "1",
            operatingSystem: "macOS 15",
            architecture: "arm64",
            modelFamily: "Portable Mac",
            metrics: [],
            conditions: [],
            energyGuardMode: .normal
        )
        let output = SystemSummaryBuilder.render(input)

        for prohibited in privateFixture {
            XCTAssertFalse(output.contains(prohibited))
        }
        XCTAssertFalse(output.contains("reading=0"))
        XCTAssertTrue(output.hasSuffix("\n"))
    }
}
