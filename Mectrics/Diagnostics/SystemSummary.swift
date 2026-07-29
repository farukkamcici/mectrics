import AppKit
import Darwin
import Foundation
import MetricsKit

struct SystemSummaryMetric: Equatable {
    let id: MetricID
    let state: MetricDataState
    let reading: String?
}

struct SystemSummaryCondition: Equatable {
    let conditionKey: String
    let metricID: MetricID
    let state: AlertConditionState
    let severity: AttentionSeverity
}

struct SystemSummaryInput: Equatable {
    let appVersion: String
    let appBuild: String
    let operatingSystem: String
    let architecture: String
    let modelFamily: String
    let metrics: [SystemSummaryMetric]
    let conditions: [SystemSummaryCondition]
    let energyGuardMode: EnergyGuardMode
}

enum SystemSummaryBuilder {
    static let schema = "mectrics.system-summary.v1"

    @MainActor
    static func capture(model: AppModel) -> SystemSummaryInput {
        let bundle = Bundle.main
        let metrics = model.orderedEnabledModules.map { id in
            let state = model.metricState(for: id, isEnabled: true)
            return SystemSummaryMetric(
                id: id,
                state: state,
                reading: model.latest[id].map {
                    formattedReading($0, metricID: id)
                }
            )
        }
        let conditions = model.activeAlertConditions.values
            .sorted { $0.conditionKey < $1.conditionKey }
            .map {
                SystemSummaryCondition(
                    conditionKey: $0.conditionKey,
                    metricID: $0.metricID,
                    state: $0.state,
                    severity: $0.severity
                )
            }
        return SystemSummaryInput(
            appVersion: bundle.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? "—",
            appBuild: bundle.object(
                forInfoDictionaryKey: "CFBundleVersion"
            ) as? String ?? "—",
            operatingSystem:
                ProcessInfo.processInfo.operatingSystemVersionString,
            architecture: architecture(),
            modelFamily: model.availableModules.contains(.battery)
                ? String(
                    localized: "summary.model.portable",
                    defaultValue: "Portable Mac"
                )
                : String(
                    localized: "summary.model.desktop",
                    defaultValue: "Desktop Mac"
                ),
            metrics: metrics,
            conditions: conditions,
            energyGuardMode: model.energyGuardMode
        )
    }

    static func render(_ input: SystemSummaryInput) -> String {
        var lines = [
            String(
                localized: "summary.title",
                defaultValue: "Mectrics System Summary"
            ),
            "Schema: \(schema)",
            "App: \(input.appVersion) (\(input.appBuild))",
            "macOS: \(input.operatingSystem)",
            "Architecture: \(input.architecture)",
            "Mac family: \(input.modelFamily)",
            "Energy Guard: \(input.energyGuardMode.rawValue)",
            "",
            String(localized: "summary.metrics", defaultValue: "Metrics:")
        ]
        if input.metrics.isEmpty {
            lines.append("- none")
        } else {
            for metric in input.metrics {
                var line =
                    "- \(metric.id.rawValue) | state=\(metric.state.rawValue)"
                if let reading = metric.reading {
                    line += " | reading=\(reading)"
                }
                lines.append(line)
            }
        }
        lines.append("")
        lines.append(
            String(
                localized: "summary.conditions",
                defaultValue: "Active conditions:"
            )
        )
        if input.conditions.isEmpty {
            lines.append("- none")
        } else {
            for condition in input.conditions {
                lines.append(
                    "- \(condition.conditionKey) | metric=\(condition.metricID.rawValue) | state=\(condition.state.rawValue) | severity=\(condition.severity.rawValue)"
                )
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    @MainActor
    static func copy(model: AppModel) -> Bool {
        let text = render(capture(model: model))
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }

    private static func formattedReading(
        _ sample: MetricSample,
        metricID: MetricID
    ) -> String {
        switch sample.unit {
        case .fraction:
            return MetricFormat.percent(sample.value, decimals: 1)
        case .percent:
            return "\(sample.value.formatted(.number.precision(.fractionLength(1))))%"
        case .bytes:
            return MetricFormat.bytes(sample.value)
        case .bytesPerSecond:
            return "\(MetricFormat.bytes(sample.value))/s"
        case .celsius:
            return "\(sample.value.formatted(.number.precision(.fractionLength(1))))°C"
        case .rpm:
            return "\(Int(sample.value.rounded())) RPM"
        case .watts:
            return "\(sample.value.formatted(.number.precision(.fractionLength(1)))) W"
        case .count:
            return Int(sample.value.rounded()).formatted()
        }
    }

    private static func architecture() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
    }
}
