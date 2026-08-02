import Foundation
import MetricsKit

enum DoctorStatus: String, Codable, Sendable {
    case ready
    case degraded
    case notConfigured
}

enum InstalledCommandState: String, Codable, Sendable {
    case installed
    case notInstalled
    case brokenLink
    case differentCommand
}

struct DoctorReport: Codable, Sendable {
    let schemaVersion: Int
    let timestamp: Date
    let status: DoctorStatus
    let version: String
    let executablePath: String
    let preferencesDomain: String
    let enabledRuleCount: Int
    let checkableConditions: [String]
    let unavailableConditions: [String]
    let installedCommand: InstalledCommandState
    let onBattery: Bool
}

@MainActor
final class CLIApplication {
    static let live = CLIApplication()

    private let output: CLIOutput
    private let providerFactory: ProviderFactory
    private let loadConfiguration: () throws -> AlertConfiguration
    private let version: String
    private let installedCommandState: () -> InstalledCommandState

    init(
        output: CLIOutput = .live,
        providerFactory: @escaping ProviderFactory = MetricsKit.coreProviders(for:),
        loadConfiguration: @escaping () throws -> AlertConfiguration = {
            try AlertConfigurationStore().load()
        },
        version: String = InstalledVersion.current,
        installedCommandState: @escaping () -> InstalledCommandState = {
            CLIApplication.inspectInstalledCommand()
        }
    ) {
        self.output = output
        self.providerFactory = providerFactory
        self.loadConfiguration = loadConfiguration
        self.version = version
        self.installedCommandState = installedCommandState
    }

    func check(json: Bool) async throws -> Int32 {
        let configuration = try loadConfiguration()
        let result: OneShotSamplingResult
        if configuration.enabledRuleCount == 0 {
            result = OneShotSamplingResult(
                samples: [:],
                unavailableMetricIDs: [],
                failedMetricIDs: [],
                timedOut: false
            )
        } else {
            result = await OneShotSampler(providerFactory: providerFactory)
                .sample(configuration.requiredMetricIDs)
        }
        let report = AlertHealthReport(
            configuration: configuration,
            latest: result.samples
        )
        output.print(json ? try CLIJSON.encode(report) : humanHealthReport(report))
        return healthExitCode(report.status)
    }

    func snapshot(json: Bool) async throws -> Int32 {
        let result = await OneShotSampler(providerFactory: providerFactory)
            .sample(Set(MetricID.allCases))
        let report = MetricSnapshotReport(latest: result.samples)
        output.print(json ? try CLIJSON.encode(report) : humanSnapshotReport(report))
        return report.metrics.isEmpty ? CLIExit.indeterminate : CLIExit.healthy
    }

    func listRules(json: Bool) throws -> Int32 {
        let list = AlertRuleList(configuration: try loadConfiguration())
        output.print(json ? try CLIJSON.encode(list) : humanRuleList(list))
        return CLIExit.healthy
    }

    func watch(json: Bool, heartbeatSeconds: Int?) async throws -> Int32 {
        let configuration = try loadConfiguration()
        let heartbeat = heartbeatSeconds.map { Duration.seconds($0) }
        let session = AlertWatchSession(
            configuration: configuration,
            heartbeatInterval: heartbeat,
            providerFactory: providerFactory,
            onLegacyEvent: { [output] event in
                do {
                    output.print(json ? try CLIJSON.encode(event) : humanAlertEvent(event))
                } catch {
                    output.diagnostic(CLIExecutionError.encodingFailed.localizedDescription)
                }
            },
            onRecord: { [output] record in
                do {
                    output.print(try CLIJSON.encode(record))
                } catch {
                    output.diagnostic(CLIExecutionError.encodingFailed.localizedDescription)
                }
            },
            onDiagnostic: { [output] message in
                output.diagnostic(message)
            }
        )
        try session.start()

        let ruleCount = configuration.enabledRuleCount
        let destination: String
        if heartbeatSeconds != nil {
            destination = "Writing tagged alert, status, and heartbeat records as NDJSON."
        } else if json {
            destination = "Waiting for a change. Each event will appear here as one JSON line."
        } else {
            destination = "Waiting for a rule to activate or recover. Events will appear here."
        }
        output.diagnostic(
            "Watching \(ruleCount) enabled alert rule\(ruleCount == 1 ? "" : "s"). "
                + destination + " Press Ctrl-C to stop."
        )
        await session.runUntilCancelled()
        return CLIExit.healthy
    }

    func doctor(json: Bool) throws -> Int32 {
        let configuration = try loadConfiguration()
        let providers = providerFactory(configuration.requiredMetricIDs)
        let availableMetricIDs = Set(providers.filter(\.isAvailable).map(\.id))
        var checkable: [String] = []
        var unavailable: [String] = []
        for rule in configuration.configuredRules {
            if let dependency = samplingMetricID(for: rule),
               !availableMetricIDs.contains(dependency) {
                unavailable.append(rule.condition)
            } else {
                checkable.append(rule.condition)
            }
        }

        let commandState = installedCommandState()
        let commandNeedsAttention = commandState == .brokenLink
            || commandState == .differentCommand
        let status: DoctorStatus
        let exitCode: Int32
        if configuration.enabledRuleCount == 0 {
            status = .notConfigured
            exitCode = CLIExit.indeterminate
        } else if !unavailable.isEmpty || commandNeedsAttention {
            status = .degraded
            exitCode = CLIExit.indeterminate
        } else {
            status = .ready
            exitCode = CLIExit.healthy
        }
        let report = DoctorReport(
            schemaVersion: 1,
            timestamp: Date(),
            status: status,
            version: version,
            executablePath: Bundle.main.executableURL?
                .resolvingSymlinksInPath().path ?? CommandLine.arguments[0],
            preferencesDomain: AlertConfigurationStore.activePreferencesDomain,
            enabledRuleCount: configuration.enabledRuleCount,
            checkableConditions: checkable.sorted(),
            unavailableConditions: unavailable.sorted(),
            installedCommand: commandState,
            onBattery: SystemPowerSource.isOnBattery
        )
        if json {
            output.print(try CLIJSON.encode(report))
        } else {
            output.print(humanDoctorReport(report))
        }
        return exitCode
    }

    func showVersion() -> Int32 {
        output.print("mectrics \(version)")
        return CLIExit.healthy
    }

    private func samplingMetricID(for rule: ConfiguredAlertRule) -> MetricID? {
        rule.condition == SystemAlertSignal.thermalPressure.conditionKey
            ? nil
            : rule.metric
    }

    nonisolated private static func inspectInstalledCommand() -> InstalledCommandState {
        let path = "/usr/local/bin/mectrics"
        let fileManager = FileManager.default
        do {
            let target = try fileManager.destinationOfSymbolicLink(atPath: path)
            let destination = URL(filePath: path).deletingLastPathComponent()
            let targetURL = target.hasPrefix("/")
                ? URL(filePath: target)
                : destination.appending(path: target)
            guard fileManager.fileExists(atPath: targetURL.path) else {
                return .brokenLink
            }
            return targetURL.resolvingSymlinksInPath().standardizedFileURL
                == Bundle.main.executableURL?.resolvingSymlinksInPath().standardizedFileURL
                ? .installed
                : .differentCommand
        } catch {
            return fileManager.fileExists(atPath: path)
                ? .differentCommand
                : .notInstalled
        }
    }

    private func humanDoctorReport(_ report: DoctorReport) -> String {
        var lines = [
            "MECTRICS DOCTOR · \(report.status.rawValue.uppercased())",
            "Version: \(report.version)",
            "Executable: \(report.executablePath)",
            "Preferences: \(report.preferencesDomain)",
            "Enabled rules: \(report.enabledRuleCount)",
            "Installed command: \(report.installedCommand.rawValue)",
            "Power source: \(report.onBattery ? "battery" : "AC")"
        ]
        if !report.checkableConditions.isEmpty {
            lines.append("Checkable: " + report.checkableConditions.joined(separator: ", "))
        }
        if !report.unavailableConditions.isEmpty {
            lines.append(
                "Unavailable: " + report.unavailableConditions.joined(separator: ", ")
            )
        }
        return lines.joined(separator: "\n")
    }
}
