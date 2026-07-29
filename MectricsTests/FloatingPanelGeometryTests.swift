import AppKit
import XCTest
@testable import Mectrics

final class FloatingPanelGeometryTests: XCTestCase {
    func testDisconnectedDisplayPlacementIsClampedToVisibleFrame() {
        let visible = NSRect(x: 0, y: 24, width: 1440, height: 876)
        let offscreen = NSRect(x: 1800, y: -200, width: 240, height: 100)

        XCTAssertEqual(
            FloatingPanelGeometry.adjustedFrame(
                offscreen,
                visibleFrame: visible,
                snap: false
            ),
            NSRect(x: 1200, y: 24, width: 240, height: 100)
        )
    }

    func testNearEdgesSnapWithoutForcingDistantMovement() {
        let visible = NSRect(x: 0, y: 24, width: 1440, height: 876)
        let nearTopRight = NSRect(x: 1193, y: 793, width: 240, height: 100)
        let center = NSRect(x: 500, y: 400, width: 240, height: 100)

        XCTAssertEqual(
            FloatingPanelGeometry.adjustedFrame(
                nearTopRight,
                visibleFrame: visible,
                snap: true
            ).origin,
            NSPoint(x: 1200, y: 800)
        )
        XCTAssertEqual(
            FloatingPanelGeometry.adjustedFrame(
                center,
                visibleFrame: visible,
                snap: true
            ),
            center
        )
    }

    func testOversizedPanelRemainsReachable() {
        let visible = NSRect(x: 100, y: 50, width: 800, height: 500)
        let oversized = NSRect(x: -100, y: -100, width: 1000, height: 700)

        XCTAssertEqual(
            FloatingPanelGeometry.adjustedFrame(
                oversized,
                visibleFrame: visible,
                snap: false
            ),
            visible
        )
    }
}
