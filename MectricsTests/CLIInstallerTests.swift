import XCTest
@testable import Mectrics

final class CLIInstallerTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "mectrics-cli-installer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testInstallationStateRecognizesTheBundledCLI() throws {
        let source = temporaryDirectory
            .appending(path: "Mectrics.app/Contents/Helpers/mectrics")
        let destination = temporaryDirectory.appending(path: "bin/mectrics")
        try FileManager.default.createDirectory(
            at: source.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: source.path, contents: Data())
        try FileManager.default.createSymbolicLink(
            at: destination,
            withDestinationURL: source
        )

        XCTAssertEqual(
            CLIInstaller.installationState(
                source: source,
                destination: destination
            ),
            .installed
        )
    }

    func testInstallationStateDoesNotClaimAnUnrelatedCommand() throws {
        let source = temporaryDirectory
            .appending(path: "Mectrics.app/Contents/Helpers/mectrics")
        let destination = temporaryDirectory.appending(path: "bin/mectrics")
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(
            atPath: destination.path,
            contents: Data()
        )

        XCTAssertEqual(
            CLIInstaller.installationState(
                source: source,
                destination: destination
            ),
            .conflict
        )
    }

    func testInstallationStateCanRepairAnOlderMectricsLink() throws {
        let source = temporaryDirectory
            .appending(path: "New/Mectrics.app/Contents/Helpers/mectrics")
        let oldSource = temporaryDirectory
            .appending(path: "Old/Mectrics.app/Contents/Helpers/mectrics")
        let destination = temporaryDirectory.appending(path: "bin/mectrics")
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: destination,
            withDestinationURL: oldSource
        )

        XCTAssertEqual(
            CLIInstaller.installationState(
                source: source,
                destination: destination
            ),
            .repairable
        )
    }

    func testInstallCommandGuardsBeforeReplacingAManagedLink() {
        let source = URL(filePath: "/Applications/Mectrics.app/Contents/Helpers/mectrics")
        let destination = URL(filePath: "/usr/local/bin/mectrics")
        let command = CLIInstaller.installCommand(
            source: source,
            destination: destination,
            existingManagedTarget: "/Old/Mectrics.app/Contents/Helpers/mectrics"
        )

        XCTAssertTrue(command.contains("/usr/bin/readlink"))
        XCTAssertTrue(command.contains("/bin/rm -f"))
        XCTAssertTrue(command.contains("/bin/ln -s"))
        XCTAssertTrue(command.contains("'/usr/local/bin/mectrics'"))
    }

    func testShellQuotingPreservesApostrophes() {
        XCTAssertEqual(
            CLIInstaller.shellQuoted("/Applications/Faruk's Apps/Mectrics.app"),
            "'/Applications/Faruk'\\''s Apps/Mectrics.app'"
        )
    }
}
