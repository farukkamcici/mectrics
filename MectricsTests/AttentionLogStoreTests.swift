import Foundation
import MetricsKit
import XCTest
@testable import Mectrics

@MainActor
final class AttentionLogStoreTests: XCTestCase {
    func testIncidentIsDeduplicatedAndRecoverySurvivesRelaunch() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("attention-log.json")
        let start = Date(timeIntervalSince1970: 10_000)
        let store = AttentionLogStore(fileURL: fileURL, now: { start })

        store.apply(update(.pending, state: .pending, measured: 91), at: start)
        store.apply(
            update(.activated, state: .active, measured: 94),
            at: start.addingTimeInterval(30)
        )
        XCTAssertEqual(store.events.count, 1)
        XCTAssertEqual(store.events[0].state, .active)
        XCTAssertNil(store.events[0].endedAt)

        store.apply(
            update(.recovered, state: .normal, measured: 42),
            at: start.addingTimeInterval(90)
        )
        XCTAssertEqual(store.events.count, 1)
        XCTAssertTrue(store.events[0].isResolved)
        XCTAssertEqual(store.events[0].recoveryResult, "recovered")

        let reloaded = AttentionLogStore(
            fileURL: fileURL,
            now: { start.addingTimeInterval(90) }
        )
        XCTAssertEqual(reloaded.events, store.events)
    }

    func testDestinationWithoutAttentionLogDoesNotCreateEvent() {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let store = AttentionLogStore(fileURL: fileURL)
        var update = update(.activated, state: .active, measured: 95)
        update = AlertConditionUpdate(
            metricID: update.metricID,
            state: update.state,
            transition: update.transition,
            measuredValue: update.measuredValue,
            thresholdValue: update.thresholdValue,
            durationSeconds: update.durationSeconds,
            startedAt: update.startedAt,
            destinations: [.notification]
        )

        store.apply(update)
        XCTAssertTrue(store.events.isEmpty)
    }

    func testRetentionCapacityClearAndExportAreDeterministic() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("attention-log.json")
        let now = Date(timeIntervalSince1970: 5_000_000)
        let store = AttentionLogStore(
            fileURL: fileURL,
            retention: 100,
            capacity: 2,
            now: { now }
        )

        store.apply(
            update(
                .activated,
                state: .active,
                measured: 91,
                startedAt: now.addingTimeInterval(-200)
            ),
            at: now.addingTimeInterval(-200)
        )
        XCTAssertTrue(store.events.isEmpty)

        for offset in [3.0, 2.0, 1.0] {
            let start = now.addingTimeInterval(-offset)
            store.apply(
                update(
                    .activated,
                    state: .active,
                    measured: 92,
                    startedAt: start
                ),
                at: start
            )
            store.apply(
                update(
                    .recovered,
                    state: .normal,
                    measured: 40,
                    startedAt: start
                ),
                at: start.addingTimeInterval(0.5)
            )
        }
        XCTAssertEqual(store.events.count, 2)

        let preview = store.exportText(generatedAt: now)
        let exportURL = directory.appendingPathComponent("preview.txt")
        try Data(preview.utf8).write(to: exportURL)
        XCTAssertEqual(try String(contentsOf: exportURL, encoding: .utf8), preview)
        XCTAssertTrue(preview.contains("Schema: mectrics.attention-log.v1"))
        for prohibited in [
            "username",
            "hostname",
            "serial number",
            "MAC address",
            "IP address",
            "process name"
        ] {
            XCTAssertFalse(preview.localizedCaseInsensitiveContains(prohibited))
        }

        store.clear()
        XCTAssertTrue(store.events.isEmpty)
        let reloaded = AttentionLogStore(fileURL: fileURL, now: { now })
        XCTAssertTrue(reloaded.events.isEmpty)
    }

    private func update(
        _ transition: AlertConditionTransition,
        state: AlertConditionState,
        measured: Double,
        startedAt: Date = Date(timeIntervalSince1970: 10_000)
    ) -> AlertConditionUpdate {
        AlertConditionUpdate(
            metricID: .cpu,
            state: state,
            transition: transition,
            measuredValue: measured,
            thresholdValue: 90,
            durationSeconds: 30,
            startedAt: startedAt,
            destinations: [.attentionLog, .notification]
        )
    }
}
