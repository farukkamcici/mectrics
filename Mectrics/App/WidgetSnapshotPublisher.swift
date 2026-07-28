import Foundation
import MetricsKit
import WidgetKit

/// Publishes a compact snapshot for WidgetKit at a deliberately low frequency. The
/// menu bar remains real-time; widgets are an at-a-glance surface managed by macOS.
@MainActor
final class WidgetSnapshotPublisher {
#if DEBUG
    private let store = SharedMetricSnapshotStore(appGroupIdentifier: nil)
#else
    private let store = SharedMetricSnapshotStore()
#endif
    private let writerQueue = DispatchQueue(
        label: "com.mectrics.widget-snapshot",
        qos: .utility
    )
    private var lastPublication = Date.distantPast
    private let minimumInterval: TimeInterval = 60

    func publish(from model: AppModel, force: Bool = false) {
        let now = Date()
        guard force || now.timeIntervalSince(lastPublication) >= minimumInterval else {
            return
        }
        let metricIDs = model.orderedEnabledModules
        let snapshot = SharedMetricSnapshot(
            generatedAt: now,
            orderedMetricIDs: metricIDs,
            samples: Dictionary(uniqueKeysWithValues: metricIDs.compactMap { id in
                model.latest[id].map { (id, $0) }
            }),
            histories: Dictionary(uniqueKeysWithValues: metricIDs.map { id in
                (id, model.history(id, count: 40))
            }),
            states: Dictionary(uniqueKeysWithValues: metricIDs.map { id in
                (id, model.metricState(for: id, isEnabled: true, now: now))
            })
        )
        lastPublication = now

        let store = store
        writerQueue.async {
            guard (try? store.write(snapshot)) != nil else { return }
            WidgetCenter.shared.reloadTimelines(ofKind: MectricsWidgetKind.value)
        }
    }
}

/// Kept in the shared app target so timeline reloads and the extension use one stable ID.
enum MectricsWidgetKind {
    static let value = "MectricsOverviewWidget"
}
