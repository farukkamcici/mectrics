import Darwin
import Foundation
import MetricsKit

private enum CLICommand {
    case alertsWatch(json: Bool)
    case alertsList(json: Bool)
    case check(json: Bool)
    case snapshot(json: Bool)
    case version
    case help
}

private enum CLIError: LocalizedError {
    case invalidArguments
    case unreadableConfiguration
    case noEnabledRules

    var errorDescription: String? {
        switch self {
        case .invalidArguments:
            return "Invalid arguments. Run mectrics --help for usage."
        case .unreadableConfiguration:
            return "The saved Mectrics alert rules could not be read."
        case .noEnabledRules:
            return "No alert rules are enabled. Enable at least one in Mectrics Settings > Alerts."
        }
    }
}

private func parseCommand(_ arguments: [String]) throws -> CLICommand {
    switch arguments {
    case []:
        return .help
    case ["alerts", "watch"]:
        return .alertsWatch(json: false)
    case ["alerts", "watch", "--json"]:
        return .alertsWatch(json: true)
    case ["alerts", "list"]:
        return .alertsList(json: false)
    case ["alerts", "list", "--json"]:
        return .alertsList(json: true)
    case ["check"]:
        return .check(json: false)
    case ["check", "--json"]:
        return .check(json: true)
    case ["snapshot"]:
        return .snapshot(json: false)
    case ["snapshot", "--json"]:
        return .snapshot(json: true)
    case ["--version"], ["version"]:
        return .version
    case ["--help"], ["-h"], ["help"]:
        return .help
    default:
        throw CLIError.invalidArguments
    }
}

private func printHelp() {
    print(
        """
        Mectrics CLI is a read-only automation interface for the alert rules
        configured in Mectrics.app.

        Usage:
          mectrics alerts watch          Wait for alert and recovery events
          mectrics alerts watch --json   Print each new event as JSON to stdout
          mectrics alerts list           List enabled alert rules
          mectrics alerts list --json    List enabled rules as JSON
          mectrics check                 Check configured alert rules once
          mectrics check --json          Write the check details as JSON
          mectrics snapshot              Read every available metric once
          mectrics snapshot --json       Write all current readings as JSON
          mectrics --version             Show the installed version
          mectrics --help                Show this help

        The CLI never changes Mectrics settings. Configure rules in the app.
        """
    )
}

private enum SavedAlertConfiguration {
    private static let preferencesDomain = "com.mectrics.app"
    private static let thresholdRulesKey = "alertRules"
    private static let systemRulesKey = "systemAlertRules"

    static func load() throws -> AlertConfiguration {
        guard let defaults = UserDefaults(suiteName: preferencesDomain) else {
            throw CLIError.unreadableConfiguration
        }
        do {
            return try AlertConfiguration.decode(
                thresholdData: defaults.data(forKey: thresholdRulesKey),
                systemData: defaults.data(forKey: systemRulesKey)
            )
        } catch {
            throw CLIError.unreadableConfiguration
        }
    }
}

@MainActor
private final class AlertWatchCommand {
    private let configuration: AlertConfiguration
    private let json: Bool
    private let engine = MetricsEngine(
        policy: SamplingPolicy(onACInterval: 1.0)
    )
    private let thresholdMonitor = ThresholdMonitor()
    private let systemMonitor = SystemConditionMonitor()
    private var latest: [MetricID: MetricSample] = [:]

    init(configuration: AlertConfiguration, json: Bool) throws {
        guard configuration.enabledRuleCount > 0 else {
            throw CLIError.noEnabledRules
        }
        self.configuration = configuration
        self.json = json
        thresholdMonitor.onConditionUpdate = { [weak self] update in
            self?.emit(update)
        }
        systemMonitor.onConditionUpdate = { [weak self] update in
            self?.emit(update)
        }
    }

    func start() {
        let requiredIDs = configuration.requiredMetricIDs
        let availableProviders = MetricsKit.coreProviders().filter {
            requiredIDs.contains($0.id) && $0.isAvailable
        }
        let availableIDs = Set(availableProviders.map(\.id))
        let unavailableIDs = requiredIDs.subtracting(availableIDs)

        if !unavailableIDs.isEmpty {
            writeToStandardError(
                "Unavailable metrics skipped: "
                    + unavailableIDs.map(\.rawValue).sorted().joined(separator: ", ")
                    + "\n"
            )
        }
        guard !availableProviders.isEmpty else {
            writeToStandardError(
                "None of the enabled alert rules can be sampled on this Mac.\n"
            )
            exit(2)
        }

        engine.register(availableProviders, alreadyFiltered: true)
        engine.setActiveMetrics(availableIDs)
        engine.onCycle = { [weak self] updated in
            self?.evaluate(updated)
        }
        engine.start()

        let ruleCount = configuration.enabledRuleCount
        let prefix = "Watching \(ruleCount) enabled alert "
            + "rule\(ruleCount == 1 ? "" : "s"). "
        let destination = json
            ? "Waiting for a change. Each event will appear here as one JSON line. "
            : "Waiting for a rule to activate or recover. Events will appear here. "
        writeToStandardError(
            prefix + destination + "Press Ctrl-C to stop.\n"
        )
    }

    private func evaluate(_ updated: [MetricID: MetricSample]) {
        latest.merge(updated) { _, new in new }
        thresholdMonitor.evaluate(
            latest: latest,
            rules: configuration.thresholdRules
        )
        systemMonitor.evaluate(
            readings: systemReadings(from: latest),
            rules: configuration.systemRules
        )
    }

    private func emit(_ update: AlertConditionUpdate) {
        guard update.transition != .pending else { return }
        let event = AlertStreamEvent(update: update)
        if json {
            writeJSON(event)
        } else {
            let timestamp = ISO8601DateFormatter().string(from: event.timestamp)
            let label = event.event == .activated ? "ALERT" : "RECOVERED"
            print(
                "\(timestamp) \(label) \(event.condition) "
                    + "\(format(event.measuredValue, unit: event.unit)) "
                    + "(threshold \(comparisonSymbol(event.comparison)) "
                    + "\(format(event.thresholdValue, unit: event.unit)))"
            )
        }
        fflush(stdout)
    }
}

@MainActor
private final class CheckCommand {
    private let configuration: AlertConfiguration
    private let json: Bool
    private let engine = MetricsEngine()
    private let availableProviders: [MetricProvider]
    private let availableIDs: Set<MetricID>
    private var latest: [MetricID: MetricSample] = [:]
    private var attempts = 0
    private var completed = false

    init(configuration: AlertConfiguration, json: Bool) {
        self.configuration = configuration
        self.json = json
        let requiredIDs = configuration.requiredMetricIDs
        let providers = MetricsKit.coreProviders().filter {
            requiredIDs.contains($0.id) && $0.isAvailable
        }
        availableProviders = providers
        availableIDs = Set(providers.map(\.id))
    }

    func start() {
        guard configuration.enabledRuleCount > 0 else {
            finish()
            return
        }
        guard !availableProviders.isEmpty else {
            finish()
            return
        }

        engine.register(availableProviders, alreadyFiltered: true)
        engine.setActiveMetrics(availableIDs)
        engine.onCycleReport = { [weak self] report in
            self?.received(report)
        }
        requestSample()
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            self?.finish()
        }
    }

    private func requestSample() {
        guard !completed else { return }
        attempts += 1
        engine.requestRefresh(includingHeavy: true)
    }

    private func received(_ report: SamplingCycleReport) {
        latest.merge(report.samples) { _, new in new }
        let missing = availableIDs.subtracting(latest.keys)
        if missing.isEmpty || attempts >= 3 {
            finish()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.requestSample()
            }
        }
    }

    private func finish() {
        guard !completed else { return }
        completed = true
        engine.stop()
        let report = AlertHealthReport(
            configuration: configuration,
            latest: latest
        )
        if json {
            writeJSON(report)
        } else {
            printStatus(report)
        }
        fflush(stdout)
        exit(exitCode(for: report.status))
    }
}

@MainActor
private final class SnapshotCommand {
    private let json: Bool
    private let engine = MetricsEngine()
    private let availableProviders: [MetricProvider]
    private let availableIDs: Set<MetricID>
    private var latest: [MetricID: MetricSample] = [:]
    private var attempts = 0
    private var completed = false

    init(json: Bool) {
        self.json = json
        let providers = MetricsKit.coreProviders().filter(\.isAvailable)
        availableProviders = providers
        availableIDs = Set(providers.map(\.id))
    }

    func start() {
        guard !availableProviders.isEmpty else {
            finish()
            return
        }

        engine.register(availableProviders, alreadyFiltered: true)
        engine.setActiveMetrics(availableIDs)
        engine.onCycleReport = { [weak self] report in
            self?.received(report)
        }
        requestSample()
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            self?.finish()
        }
    }

    private func requestSample() {
        guard !completed else { return }
        attempts += 1
        engine.requestRefresh(includingHeavy: true)
    }

    private func received(_ report: SamplingCycleReport) {
        latest.merge(report.samples) { _, new in new }
        let missing = availableIDs.subtracting(latest.keys)
        if missing.isEmpty || attempts >= 3 {
            finish()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.requestSample()
            }
        }
    }

    private func finish() {
        guard !completed else { return }
        completed = true
        engine.stop()
        let report = MetricSnapshotReport(latest: latest)
        if json {
            writeJSON(report)
        } else {
            printSnapshot(report)
        }
        fflush(stdout)
        exit(report.metrics.isEmpty ? 2 : 0)
    }
}

private func printRules(_ configuration: AlertConfiguration, json: Bool) {
    let list = AlertRuleList(configuration: configuration)
    if json {
        writeJSON(list)
        return
    }
    guard !list.rules.isEmpty else {
        print("No alert rules are enabled.")
        return
    }
    for rule in list.rules {
        print(
            "\(rule.condition): \(comparisonSymbol(rule.comparison)) "
                + "\(format(rule.thresholdValue, unit: rule.unit)) "
                + "for \(rule.durationSeconds)s"
        )
    }
}

private func printStatus(_ report: AlertHealthReport) {
    switch report.status {
    case .healthy:
        print("HEALTHY · \(report.conditions.count) rules checked")
    case .attention:
        let count = report.conditions.filter {
            $0.state == .limitCrossed
        }.count
        print("ATTENTION · \(count) current limit\(count == 1 ? "" : "s") crossed")
    case .unavailable:
        let count = report.conditions.filter {
            $0.state == .unavailable
        }.count
        print("UNAVAILABLE · \(count) rule\(count == 1 ? "" : "s") could not be checked")
    case .notConfigured:
        print("NOT CONFIGURED · Enable alert rules in Mectrics Settings > Alerts")
    }

    for condition in report.conditions {
        let label: String
        switch condition.state {
        case .normal: label = "OK"
        case .limitCrossed: label = "LIMIT CROSSED"
        case .unavailable: label = "UNAVAILABLE"
        }
        if let measured = condition.measuredValue {
            print(
                "\(label) \(condition.condition): "
                    + "\(format(measured, unit: condition.unit)) "
                    + "(threshold \(comparisonSymbol(condition.comparison)) "
                    + "\(format(condition.thresholdValue, unit: condition.unit)))"
            )
        } else {
            print("\(label) \(condition.condition)")
        }
    }
}

private func printSnapshot(_ report: MetricSnapshotReport) {
    guard !report.metrics.isEmpty else {
        print("UNAVAILABLE · No metrics could be sampled")
        return
    }
    print("SNAPSHOT · \(report.metrics.count) metrics")
    for reading in report.metrics {
        print(
            "\(reading.metric.displayName): "
                + format(reading.value, unit: reading.unit)
        )
    }
    if !report.unavailable.isEmpty {
        print(
            "Unavailable: "
                + report.unavailable.map(\.displayName).joined(separator: ", ")
        )
    }
}

private func exitCode(for status: AlertHealthStatus) -> Int32 {
    switch status {
    case .healthy: return 0
    case .attention: return 1
    case .unavailable, .notConfigured: return 2
    }
}

private func systemReadings(
    from latest: [MetricID: MetricSample]
) -> [SystemAlertSignal: SystemConditionReading] {
    SystemConditionSource.readings(latest: latest)
}

private func comparisonSymbol(_ comparison: AlertComparison) -> String {
    comparison == .atOrBelow ? "<=" : ">="
}

private func format(_ value: Double, unit: MetricUnit) -> String {
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

private func writeJSON<T: Encodable>(_ value: T) {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    guard let data = try? encoder.encode(value),
          let output = String(data: data, encoding: .utf8)
    else {
        writeToStandardError("Could not encode JSON output.\n")
        exit(2)
    }
    print(output)
}

private func writeToStandardError(_ message: String) {
    FileHandle.standardError.write(Data(message.utf8))
}

private var installedVersion: String {
    if let version = Bundle.main.object(
        forInfoDictionaryKey: "CFBundleShortVersionString"
    ) as? String {
        return version
    }

    guard let executableURL = Bundle.main.executableURL?
        .resolvingSymlinksInPath()
    else {
        return "development"
    }
    let contentsURL = executableURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    guard contentsURL.lastPathComponent == "Contents",
          let data = try? Data(
              contentsOf: contentsURL.appendingPathComponent("Info.plist")
          ),
          let propertyList = try? PropertyListSerialization.propertyList(
              from: data,
              format: nil
          ),
          let info = propertyList as? [String: Any],
          let version = info["CFBundleShortVersionString"] as? String
    else {
        return "development"
    }
    return version
}

do {
    let command = try parseCommand(Array(CommandLine.arguments.dropFirst()))
    switch command {
    case let .alertsWatch(json):
        let configuration = try SavedAlertConfiguration.load()
        let watch = try AlertWatchCommand(
            configuration: configuration,
            json: json
        )
        watch.start()
        RunLoop.main.run()
    case let .alertsList(json):
        printRules(try SavedAlertConfiguration.load(), json: json)
    case let .check(json):
        let check = CheckCommand(
            configuration: try SavedAlertConfiguration.load(),
            json: json
        )
        check.start()
        RunLoop.main.run()
    case let .snapshot(json):
        let snapshot = SnapshotCommand(json: json)
        snapshot.start()
        RunLoop.main.run()
    case .version:
        print("mectrics \(installedVersion)")
    case .help:
        printHelp()
    }
} catch {
    writeToStandardError("\(error.localizedDescription)\n")
    exit(2)
}
