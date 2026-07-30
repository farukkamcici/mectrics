import Foundation
import MetricsKit

/// The complete set of destinations that Mectrics accepts from external sources.
///
/// Parsing is deliberately strict: routes cannot contain credentials, ports, query
/// items, or fragments, and metric identifiers must be known `MetricID` values.
enum ApplicationRoute: Equatable, Sendable {
    static let scheme = "mectrics"

    case overview
    case metric(MetricID)
    case alerts
    case attentionLog
    case about
    case whatsNew
    case diagnostics

    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme,
              url.user == nil,
              url.password == nil,
              url.port == nil,
              url.query == nil,
              url.fragment == nil,
              let host = url.host?.lowercased()
        else { return nil }

        let components = url.pathComponents.filter { $0 != "/" }
        switch (host, components) {
        case ("overview", []):
            self = .overview
        case ("metric", let metricComponents) where metricComponents.count == 1:
            guard let metricID = MetricID(
                rawValue: metricComponents[0].lowercased()
            ), Self.routableMetricIDs.contains(metricID) else {
                return nil
            }
            self = .metric(metricID)
        case ("alerts", []):
            self = .alerts
        case ("attention-log", []):
            self = .attentionLog
        case ("about", []):
            self = .about
        case ("whats-new", []):
            self = .whatsNew
        case ("diagnostics", []):
            self = .diagnostics
        default:
            return nil
        }
    }

    var url: URL {
        let rawValue = switch self {
        case .overview:
            "\(Self.scheme)://overview"
        case .metric(let metricID):
            "\(Self.scheme)://metric/\(metricID.rawValue)"
        case .alerts:
            "\(Self.scheme)://alerts"
        case .attentionLog:
            "\(Self.scheme)://attention-log"
        case .about:
            "\(Self.scheme)://about"
        case .whatsNew:
            "\(Self.scheme)://whats-new"
        case .diagnostics:
            "\(Self.scheme)://diagnostics"
        }
        // Every case above is assembled from fixed literals or a closed enum value.
        return URL(string: rawValue)!
    }

    private static let routableMetricIDs: Set<MetricID> = [
        .cpu,
        .memory,
        .battery,
        .network,
        .disk,
        .gpu,
        .sensors,
        .fans
    ]
}
