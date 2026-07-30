import XCTest
@testable import Mectrics

final class UninstallerTests: XCTestCase {
    private let home = URL(filePath: "/Users/test")

    func testEveryPathTheAppWritesToIsRemoved() {
        let paths = Uninstaller.dataPaths(home: home).map(\.path)
        XCTAssertEqual(paths, [
            "/Users/test/Library/Preferences/com.mectrics.app.plist",
            "/Users/test/Library/Group Containers/group.com.mectrics.app",
            "/Users/test/Library/Application Support/Mectrics",
            "/Users/test/Library/Caches/com.mectrics.app",
            "/Users/test/Library/Caches/com.mectrics.app.sparkle",
            "/Users/test/Library/HTTPStorages/com.mectrics.app",
            "/Users/test/Library/Saved Application State/com.mectrics.app.savedState"
        ])
    }

    func testWidgetContainerIsLeftAlone() {
        // containermanagerd refuses it without Full Disk Access, which this app does not
        // request. Listing it would only produce a removal that silently fails.
        XCTAssertFalse(
            Uninstaller.dataPaths(home: home).contains { $0.path.contains("Library/Containers") }
        )
    }

    func testHelperWaitsForTheAppToExitBeforeDeletingPreferences() {
        let script = Uninstaller.helperScript(pid: 4242, paths: [])
        let wait = try! XCTUnwrap(script.range(of: "kill -0 4242"))
        let delete = try! XCTUnwrap(script.range(of: "defaults delete com.mectrics.app"))
        // A terminating Mectrics rewrites its preferences; deleting first loses the race.
        XCTAssertTrue(
            wait.lowerBound < delete.lowerBound,
            "the helper must wait for the process to exit before clearing preferences"
        )
    }

    func testHelperRemovesItself() {
        XCTAssertTrue(Uninstaller.helperScript(pid: 1, paths: []).contains("rm -f \"$0\""))
    }

    func testPathsWithSpacesAndQuotesSurviveTheShell() {
        let script = Uninstaller.helperScript(
            pid: 1,
            paths: [URL(filePath: "/Users/o'brien/Library/Application Support/Mectrics")]
        )
        XCTAssertTrue(script.contains("'/Users/o'\\''brien/Library/Application Support/Mectrics'"))
    }

    func testGeneratedHelperHasValidShellSyntax() throws {
        let script = Uninstaller.helperScript(
            pid: 1,
            paths: [URL(filePath: "/Users/o'brien/Library/Application Support/Mectrics")]
        )
        let temporaryURL = FileManager.default.temporaryDirectory
            .appending(path: "mectrics-uninstaller-test-\(UUID().uuidString).sh")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        try script.write(to: temporaryURL, atomically: true, encoding: .utf8)

        let shell = Process()
        shell.executableURL = URL(filePath: "/bin/sh")
        shell.arguments = ["-n", temporaryURL.path(percentEncoded: false)]
        try shell.run()
        shell.waitUntilExit()

        XCTAssertEqual(shell.terminationStatus, 0)
    }

    func testHelperAbortsRatherThanDeletingWhileAppIsStillRunning() {
        let script = Uninstaller.helperScript(pid: 4242, paths: [])
        let timeout = try! XCTUnwrap(script.range(of: "if [ $i -ge 100 ]"))
        let abort = try! XCTUnwrap(script.range(of: "exit 1"))
        let delete = try! XCTUnwrap(script.range(of: "defaults delete com.mectrics.app"))

        XCTAssertTrue(timeout.lowerBound < abort.lowerBound)
        XCTAssertTrue(abort.lowerBound < delete.lowerBound)
    }

    func testSparkleCacheIsRemoved() {
        XCTAssertTrue(
            Uninstaller.dataPaths(home: home).contains {
                $0.path == "/Users/test/Library/Caches/com.mectrics.app.sparkle"
            }
        )
    }

    func testEveryRemovalTargetStaysInsideTheProvidedHome() {
        for path in Uninstaller.dataPaths(home: home) {
            XCTAssertTrue(
                path.path.hasPrefix(home.path + "/"),
                "unexpected removal target outside the home directory: \(path.path)"
            )
        }
    }
}
