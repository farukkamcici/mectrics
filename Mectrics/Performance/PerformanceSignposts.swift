import Foundation
import os

/// Local points of interest for Instruments. Signposts never leave the Mac and add
/// no telemetry or persisted diagnostics to production builds.
enum PerformanceSignposts {
    private static let log = OSLog(
        subsystem: "com.mectrics.app",
        category: .pointsOfInterest
    )
    private static let launchIntervalID = OSSignpostID(log: log)

    static func beginLaunch() {
        os_signpost(
            .begin,
            log: log,
            name: "Launch to First Sample",
            signpostID: launchIntervalID
        )
    }

    static func providersReady(count: Int) {
        os_signpost(
            .event,
            log: log,
            name: "Providers Ready",
            "Available providers: %d",
            count
        )
    }

    static func menuBarReady() {
        os_signpost(.event, log: log, name: "Menu Bar Ready")
    }

    static func engineStarted() {
        os_signpost(.event, log: log, name: "Engine Started")
    }

    static func firstSample(metricCount: Int) {
        os_signpost(
            .event,
            log: log,
            name: "First Sample",
            "Sampled metrics: %d",
            metricCount
        )
        os_signpost(
            .end,
            log: log,
            name: "Launch to First Sample",
            signpostID: launchIntervalID
        )
    }

    static func beginModulePopover() -> OSSignpostID {
        let id = OSSignpostID(log: log)
        os_signpost(
            .begin,
            log: log,
            name: "Module Popover Presentation",
            signpostID: id
        )
        return id
    }

    static func endModulePopover(_ id: OSSignpostID) {
        os_signpost(
            .end,
            log: log,
            name: "Module Popover Presentation",
            signpostID: id
        )
    }

    static func beginHealthPopover() -> OSSignpostID {
        let id = OSSignpostID(log: log)
        os_signpost(
            .begin,
            log: log,
            name: "Health Popover Presentation",
            signpostID: id
        )
        return id
    }

    static func endHealthPopover(_ id: OSSignpostID) {
        os_signpost(
            .end,
            log: log,
            name: "Health Popover Presentation",
            signpostID: id
        )
    }
}
