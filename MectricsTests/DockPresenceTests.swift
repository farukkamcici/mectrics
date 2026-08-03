import AppKit
import XCTest
@testable import Mectrics

@MainActor
final class DockPresenceTests: XCTestCase {
    private final class Window {}

    /// A menu bar agent launches with no Dock icon at all.
    func testNothingOpenMeansNoDockIcon() {
        var applied: [NSApplication.ActivationPolicy] = []
        let dock = DockPresence { applied.append($0) }

        XCTAssertFalse(dock.showsDockIcon)
        XCTAssertTrue(applied.isEmpty)
    }

    func testOpeningAWindowShowsTheDockIcon() {
        var applied: [NSApplication.ActivationPolicy] = []
        let dock = DockPresence { applied.append($0) }
        let settings = Window()

        dock.windowDidOpen(settings)

        XCTAssertTrue(dock.showsDockIcon)
        XCTAssertEqual(applied, [.regular])
    }

    /// The icon has to go away when the last window closes — the bug this replaced left
    /// it on screen because a scan of `NSApp.windows` always found a status item.
    func testClosingTheLastWindowHidesTheDockIcon() {
        let dock = DockPresence { _ in }
        let settings = Window()

        dock.windowDidOpen(settings)
        dock.windowWillClose(settings)

        XCTAssertFalse(dock.showsDockIcon)
    }

    /// Closing one of several windows is not the last one.
    func testTheIconSurvivesUntilEveryWindowIsClosed() {
        let dock = DockPresence { _ in }
        let settings = Window()
        let attentionLog = Window()

        dock.windowDidOpen(settings)
        dock.windowDidOpen(attentionLog)
        dock.windowWillClose(settings)
        XCTAssertTrue(dock.showsDockIcon)

        dock.windowWillClose(attentionLog)
        XCTAssertFalse(dock.showsDockIcon)
    }

    /// A controller reuses one window, so showing an already-open window again must not
    /// make it take two closes to disappear.
    func testShowingTheSameWindowTwiceStillClosesOnce() {
        let dock = DockPresence { _ in }
        let settings = Window()

        dock.windowDidOpen(settings)
        dock.windowDidOpen(settings)
        dock.windowWillClose(settings)

        XCTAssertFalse(dock.showsDockIcon)
    }

    /// A close for a window that was never open cannot drag the app out of the Dock
    /// while another window is still on screen.
    func testAnUnknownCloseIsIgnored() {
        let dock = DockPresence { _ in }
        let settings = Window()
        let stranger = Window()

        dock.windowDidOpen(settings)
        dock.windowWillClose(stranger)

        XCTAssertTrue(dock.showsDockIcon)
    }

    /// End to end through a real window: the reported bug was that pressing the close
    /// button left the icon in the Dock. About is used because it is the one standard
    /// window that needs nothing but the Dock policy to exist.
    func testClosingARealWindowGivesUpTheDockIcon() {
        let dock = DockPresence { _ in }
        let controller = AboutWindowController(dock: dock)

        controller.show()
        XCTAssertTrue(dock.showsDockIcon)

        guard let window = NSApp.windows.first(where: { $0.delegate === controller })
        else { return XCTFail("About window was never put on screen") }
        window.performClose(nil)

        XCTAssertFalse(
            dock.showsDockIcon,
            "The Dock icon outlived the window that asked for it"
        )
    }

    /// Reopening after the last close promotes the app again rather than assuming the
    /// policy is still `.regular`.
    func testReopeningAsksForTheDockIconAgain() {
        var applied: [NSApplication.ActivationPolicy] = []
        let dock = DockPresence { applied.append($0) }
        let settings = Window()

        dock.windowDidOpen(settings)
        dock.windowWillClose(settings)
        dock.windowDidOpen(settings)

        XCTAssertEqual(applied.filter { $0 == .regular }.count, 2)
    }
}
