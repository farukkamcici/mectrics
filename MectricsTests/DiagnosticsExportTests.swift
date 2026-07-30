import MetricsKit
import XCTest
@testable import Mectrics

final class DiagnosticsExportTests: XCTestCase {
    func testPreviewAndSavedBytesComeFromTheSameDeterministicRender() {
        let input = fixture()
        let sections: Set<DiagnosticsSection> = [.widget]
        let english = Locale(identifier: "en")
        let preview = DiagnosticsBuilder.render(
            input,
            sections: sections,
            locale: english
        )
        let exportBytes = Data(
            DiagnosticsBuilder.render(
                input,
                sections: sections,
                locale: english
            ).utf8
        )

        XCTAssertEqual(exportBytes, Data(preview.utf8))
        XCTAssertEqual(
            preview,
            """
            Mectrics Diagnostics
            Schema: mectrics.diagnostics.v1
            Generated: 1970-01-01T00:00:00Z

            ## Widget Status
            Embedded: yes
            Signed: yes
            Registered: unknown
            Gallery visible: unknown
            Snapshot readable: yes
            Note: registration and gallery visibility are system-managed and are reported as unknown when no public in-app status is available.

            """
        )
    }

    func testEveryProhibitedFieldClassIsRedacted() {
        let privateFixture = """
        Username: private-user
        Hostname: private-host.local
        Process: secret-process
        Serial Number: ABC123PRIVATE
        IP Address: 192.168.1.55
        MAC Address: aa:bb:cc:dd:ee:ff
        Wi-Fi Name: Private Network
        Bluetooth Name: Private Headphones
        Path: /Users/private-user/Documents/secret.txt
        """
        let output = DiagnosticsRedactor.redact(privateFixture)

        for prohibited in [
            "private-user",
            "private-host.local",
            "secret-process",
            "ABC123PRIVATE",
            "192.168.1.55",
            "aa:bb:cc:dd:ee:ff",
            "Private Network",
            "Private Headphones",
            "/Users/private-user"
        ] {
            XCTAssertFalse(output.contains(prohibited), prohibited)
        }
    }

    @MainActor
    func testBoundedApplicationLogKeepsOnlyAllowlistedRecentCodes() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("log.json")
        var now = Date(timeIntervalSince1970: 100)
        let store = DiagnosticLogStore(
            fileURL: fileURL,
            capacity: 2,
            retention: 50,
            now: { now }
        )

        store.record(.appLaunched)
        now = Date(timeIntervalSince1970: 125)
        store.record(.samplingStarted)
        now = Date(timeIntervalSince1970: 175)
        store.record(.powerSourceChanged)

        XCTAssertEqual(
            store.entries.map(\.code),
            [.samplingStarted, .powerSourceChanged]
        )
        try? FileManager.default.removeItem(at: directory)
    }

    private func fixture() -> DiagnosticsInput {
        DiagnosticsInput(
            generatedAt: Date(timeIntervalSince1970: 0),
            systemSummary: SystemSummaryInput(
                appVersion: "1.0",
                appBuild: "2",
                operatingSystem: "macOS",
                architecture: "arm64",
                modelFamily: "Portable Mac",
                metrics: [],
                conditions: [],
                energyGuardMode: .normal
            ),
            applicationLog: [],
            providers: [],
            alertConfigurations: [],
            widget: WidgetDiagnosticFacts(
                embedded: .yes,
                signed: .yes,
                registered: .unknown,
                galleryVisible: .unknown,
                snapshotReadable: .yes
            ),
            attentionLog: "No attention events.\n"
        )
    }
}
