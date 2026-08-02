import Foundation
import MetricsKit

func comparisonSymbol(_ comparison: AlertComparison) -> String {
    comparison == .atOrBelow ? "<=" : ">="
}

func formatMetricValue(_ value: Double, unit: MetricUnit) -> String {
    switch unit {
    case .fraction:
        return String(format: "%.1f%%", value * 100)
    case .percent:
        return String(format: "%.0f%%", value)
    case .bytesPerSecond:
        return MetricFormat.bytesPerSecond(value)
    case .celsius:
        return String(format: "%.1f°C", value)
    case .bytes:
        return MetricFormat.bytes(value)
    case .rpm:
        return String(format: "%.0f RPM", value)
    case .watts:
        return String(format: "%.1f W", value)
    case .count:
        return String(format: "%.0f", value)
    }
}

func healthExitCode(_ status: AlertHealthStatus) -> Int32 {
    switch status {
    case .healthy: return CLIExit.healthy
    case .attention: return CLIExit.attention
    case .unavailable, .notConfigured: return CLIExit.indeterminate
    }
}

func humanHealthReport(_ report: AlertHealthReport) -> String {
    var lines: [String] = []
    switch report.status {
    case .healthy:
        lines.append("HEALTHY · \(report.conditions.count) rules checked")
    case .attention:
        let count = report.conditions.filter {
            $0.state == .limitCrossed
        }.count
        lines.append(
            "ATTENTION · \(count) current limit\(count == 1 ? "" : "s") crossed"
        )
    case .unavailable:
        let count = report.conditions.filter {
            $0.state == .unavailable
        }.count
        lines.append(
            "UNAVAILABLE · \(count) rule\(count == 1 ? "" : "s") could not be checked"
        )
    case .notConfigured:
        lines.append("NOT CONFIGURED · Enable alert rules in Mectrics Settings > Alerts")
    }

    for condition in report.conditions {
        let label: String
        switch condition.state {
        case .normal: label = "OK"
        case .limitCrossed: label = "LIMIT CROSSED"
        case .unavailable: label = "UNAVAILABLE"
        }
        if let measured = condition.measuredValue {
            lines.append(
                "\(label) \(condition.condition): "
                    + "\(formatMetricValue(measured, unit: condition.unit)) "
                    + "(threshold \(comparisonSymbol(condition.comparison)) "
                    + "\(formatMetricValue(condition.thresholdValue, unit: condition.unit)))"
            )
        } else {
            lines.append("\(label) \(condition.condition)")
        }
    }
    return lines.joined(separator: "\n")
}

func humanSnapshotReport(_ report: MetricSnapshotReport) -> String {
    guard !report.metrics.isEmpty else {
        return "UNAVAILABLE · No metrics could be sampled"
    }
    var lines = ["SNAPSHOT · \(report.metrics.count) metrics"]
    lines.append(contentsOf: report.metrics.map { reading in
        "\(reading.metric.displayName): "
            + formatMetricValue(reading.value, unit: reading.unit)
    })
    if !report.unavailable.isEmpty {
        lines.append(
            "Unavailable: "
                + report.unavailable.map(\.displayName).joined(separator: ", ")
        )
    }
    return lines.joined(separator: "\n")
}

func humanRuleList(_ list: AlertRuleList) -> String {
    guard !list.rules.isEmpty else { return "No alert rules are enabled." }
    return list.rules.map { rule in
        "\(rule.condition): \(comparisonSymbol(rule.comparison)) "
            + "\(formatMetricValue(rule.thresholdValue, unit: rule.unit)) "
            + "for \(rule.durationSeconds)s"
    }.joined(separator: "\n")
}

func humanAlertEvent(_ event: AlertStreamEvent) -> String {
    let timestamp = ISO8601DateFormatter().string(from: event.timestamp)
    let label = event.event == .activated ? "ALERT" : "RECOVERED"
    return "\(timestamp) \(label) \(event.condition) "
        + "\(formatMetricValue(event.measuredValue, unit: event.unit)) "
        + "(threshold \(comparisonSymbol(event.comparison)) "
        + "\(formatMetricValue(event.thresholdValue, unit: event.unit)))"
}
