import AppKit
import MetricsKit

enum MetricContextualAction: Equatable {
    case activityMonitor
    case storageSettings
    case batterySettings
    case networkSettings
    case copyLocalAddress

    static func actions(
        for metricID: MetricID,
        hasLocalAddress: Bool
    ) -> [MetricContextualAction] {
        switch metricID {
        case .cpu, .memory, .gpu:
            return [.activityMonitor]
        case .disk:
            return [.storageSettings]
        case .battery:
            return [.batterySettings]
        case .network:
            return hasLocalAddress
                ? [.networkSettings, .copyLocalAddress]
                : [.networkSettings]
        case .sensors, .fans:
            return []
        }
    }
}

@MainActor
enum MetricContextualActionRunner {
    static func run(
        _ action: MetricContextualAction,
        localAddress: (interface: String, address: String)? = nil
    ) -> Bool {
        switch action {
        case .activityMonitor:
            return openApplication(
                atPath: "/System/Applications/Utilities/Activity Monitor.app"
            )
        case .storageSettings:
            return openSettings("com.apple.settings.Storage")
        case .batterySettings:
            return openSettings("com.apple.settings.Battery")
        case .networkSettings:
            return openSettings("com.apple.Network-Settings.extension")
        case .copyLocalAddress:
            guard let localAddress else { return false }
            let visibleValue = "\(localAddress.address) (\(localAddress.interface))"
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            return pasteboard.setString(visibleValue, forType: .string)
        }
    }

    private static func openSettings(_ paneIdentifier: String) -> Bool {
        guard let url = URL(
            string: "x-apple.systempreferences:\(paneIdentifier)"
        ) else { return false }
        return NSWorkspace.shared.open(url)
    }

    private static func openApplication(atPath path: String) -> Bool {
        let url = URL(fileURLWithPath: path, isDirectory: true)
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        NSWorkspace.shared.openApplication(
            at: url,
            configuration: NSWorkspace.OpenConfiguration()
        )
        return true
    }
}
