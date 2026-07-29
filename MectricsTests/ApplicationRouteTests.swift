import MetricsKit
import XCTest
@testable import Mectrics

final class ApplicationRouteTests: XCTestCase {
    func testEveryAllowlistedRouteRoundTrips() {
        let routes: [ApplicationRoute] = [
            .overview,
            .metric(.cpu),
            .metric(.memory),
            .metric(.battery),
            .metric(.network),
            .metric(.disk),
            .metric(.gpu),
            .metric(.sensors),
            .metric(.fans),
            .metric(.bluetooth),
            .alerts,
            .attentionLog,
            .about,
            .whatsNew,
            .diagnostics
        ]

        for route in routes {
            XCTAssertEqual(ApplicationRoute(url: route.url), route)
        }
    }

    func testRejectsUnknownAndMalformedRoutes() {
        let rejected = [
            "https://overview",
            "mectrics://unknown",
            "mectrics://metric",
            "mectrics://metric/not-a-metric",
            "mectrics://metric/clock",
            "mectrics://metric/cpu/extra",
            "mectrics://alerts/extra",
            "mectrics://overview?command=quit",
            "mectrics://overview#fragment",
            "mectrics://user@example.com/overview",
            "mectrics://overview:1234"
        ]

        for rawURL in rejected {
            XCTAssertNil(ApplicationRoute(url: URL(string: rawURL)!))
        }
    }

    func testMetricIdentifiersAreCaseInsensitiveButRemainAllowlisted() {
        XCTAssertEqual(
            ApplicationRoute(url: URL(string: "mectrics://metric/CPU")!),
            .metric(.cpu)
        )
        XCTAssertNil(ApplicationRoute(url: URL(string: "mectrics://metric/cpu%2Falerts")!))
    }

    func testContextualActionsStayRestrainedAndMetricSpecific() {
        XCTAssertEqual(
            MetricContextualAction.actions(for: .cpu, hasLocalAddress: false),
            [.activityMonitor]
        )
        XCTAssertEqual(
            MetricContextualAction.actions(for: .memory, hasLocalAddress: false),
            [.activityMonitor]
        )
        XCTAssertEqual(
            MetricContextualAction.actions(for: .disk, hasLocalAddress: false),
            [.storageSettings]
        )
        XCTAssertEqual(
            MetricContextualAction.actions(for: .battery, hasLocalAddress: false),
            [.batterySettings]
        )
        XCTAssertEqual(
            MetricContextualAction.actions(for: .network, hasLocalAddress: true),
            [.networkSettings, .copyLocalAddress]
        )
        XCTAssertEqual(
            MetricContextualAction.actions(for: .network, hasLocalAddress: false),
            [.networkSettings]
        )
        XCTAssertEqual(
            MetricContextualAction.actions(for: .bluetooth, hasLocalAddress: false),
            [.bluetoothSettings]
        )
        XCTAssertTrue(
            MetricContextualAction.actions(for: .sensors, hasLocalAddress: false).isEmpty
        )
        XCTAssertTrue(
            MetricContextualAction.actions(for: .fans, hasLocalAddress: false).isEmpty
        )
    }
}
