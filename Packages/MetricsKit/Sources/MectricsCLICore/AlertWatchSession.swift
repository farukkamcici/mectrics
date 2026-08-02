import Foundation
import MetricsKit

enum WatchRecordType: String, Codable, Sendable {
    case ready
    case heartbeat
    case alert
    case status
}

enum WatchCoverageStatus: String, Codable, Sendable {
    case collecting
    case healthy
    case degraded
}

struct WatchCoverageSnapshot: Equatable, Sendable {
    let status: WatchCoverageStatus
    let watchedConditions: [String]
    let unavailableConditions: [String]
    let collectingConditions: [String]
    let staleMetrics: [MetricID]
    let lastSampleAt: Date?
}

struct WatchStreamRecord: Codable, Sendable {
    let schemaVersion: Int
    let type: WatchRecordType
    let timestamp: Date
    let status: WatchCoverageStatus?
    let watchedConditions: [String]?
    let unavailableConditions: [String]?
    let collectingConditions: [String]?
    let staleMetrics: [MetricID]?
    let lastSampleAt: Date?
    let alert: AlertStreamEvent?

    static func ready(
        _ coverage: WatchCoverageSnapshot,
        timestamp: Date = Date()
    ) -> Self {
        Self(
            schemaVersion: 1,
            type: .ready,
            timestamp: timestamp,
            status: coverage.status,
            watchedConditions: coverage.watchedConditions,
            unavailableConditions: coverage.unavailableConditions,
            collectingConditions: coverage.collectingConditions,
            staleMetrics: coverage.staleMetrics,
            lastSampleAt: coverage.lastSampleAt,
            alert: nil
        )
    }

    static func heartbeat(
        _ coverage: WatchCoverageSnapshot,
        timestamp: Date = Date()
    ) -> Self {
        Self(
            schemaVersion: 1,
            type: .heartbeat,
            timestamp: timestamp,
            status: coverage.status,
            watchedConditions: nil,
            unavailableConditions: coverage.unavailableConditions,
            collectingConditions: coverage.collectingConditions,
            staleMetrics: coverage.staleMetrics,
            lastSampleAt: coverage.lastSampleAt,
            alert: nil
        )
    }

    static func status(
        _ coverage: WatchCoverageSnapshot,
        timestamp: Date = Date()
    ) -> Self {
        Self(
            schemaVersion: 1,
            type: .status,
            timestamp: timestamp,
            status: coverage.status,
            watchedConditions: nil,
            unavailableConditions: coverage.unavailableConditions,
            collectingConditions: coverage.collectingConditions,
            staleMetrics: coverage.staleMetrics,
            lastSampleAt: coverage.lastSampleAt,
            alert: nil
        )
    }

    static func alert(
        _ event: AlertStreamEvent,
        timestamp: Date = Date()
    ) -> Self {
        Self(
            schemaVersion: 1,
            type: .alert,
            timestamp: timestamp,
            status: nil,
            watchedConditions: nil,
            unavailableConditions: nil,
            collectingConditions: nil,
            staleMetrics: nil,
            lastSampleAt: nil,
            alert: event
        )
    }
}

@MainActor
final class AlertWatchSession {
    typealias LegacyEventHandler = (AlertStreamEvent) -> Void
    typealias RecordHandler = (WatchStreamRecord) -> Void
    typealias DiagnosticHandler = (String) -> Void

    private let configuration: AlertConfiguration
    private let heartbeatInterval: Duration?
    private let providerFactory: ProviderFactory
    private let onLegacyEvent: LegacyEventHandler
    private let onRecord: RecordHandler
    private let onDiagnostic: DiagnosticHandler
    private let staleAfter: TimeInterval
    private let engine = MetricsEngine(
        policy: SamplingPolicy(onACInterval: 1, onBatteryInterval: 2)
    )
    private let thresholdMonitor = ThresholdMonitor()
    private let systemMonitor = SystemConditionMonitor()
    private let thermalMonitor = SystemConditionMonitor()

    private var latest: [MetricID: MetricSample] = [:]
    private var consecutiveFailures: [MetricID: Int] = [:]
    private var availableMetricIDs: Set<MetricID> = []
    private var unavailableMetricIDs: Set<MetricID> = []
    private var configuredRules: [ConfiguredAlertRule] = []
    private var lastCoverage: WatchCoverageSnapshot?
    private var currentPowerState = SystemPowerSource.isOnBattery
    private var samplingTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?

    init(
        configuration: AlertConfiguration,
        heartbeatInterval: Duration?,
        providerFactory: @escaping ProviderFactory = MetricsKit.coreProviders(for:),
        staleAfter: TimeInterval = 15,
        onLegacyEvent: @escaping LegacyEventHandler,
        onRecord: @escaping RecordHandler,
        onDiagnostic: @escaping DiagnosticHandler
    ) {
        self.configuration = configuration
        self.heartbeatInterval = heartbeatInterval
        self.providerFactory = providerFactory
        self.staleAfter = staleAfter
        self.onLegacyEvent = onLegacyEvent
        self.onRecord = onRecord
        self.onDiagnostic = onDiagnostic
    }

    func start() throws {
        guard configuration.enabledRuleCount > 0 else {
            throw CLIExecutionError.noEnabledRules
        }

        configuredRules = configuration.configuredRules
        let requestedMetricIDs = configuration.requiredMetricIDs
        let providers = providerFactory(requestedMetricIDs)
        let availableProviders = providers.filter(\.isAvailable)
        availableMetricIDs = Set(availableProviders.map(\.id))
        unavailableMetricIDs = requestedMetricIDs.subtracting(availableMetricIDs)

        let checkableRules = configuredRules.filter { rule in
            guard let dependency = samplingMetricID(for: rule) else { return true }
            return availableMetricIDs.contains(dependency)
        }
        guard !checkableRules.isEmpty else {
            throw CLIExecutionError.noCheckableRules
        }

        let skippedConditions = configuredRules.compactMap { rule -> String? in
            guard let dependency = samplingMetricID(for: rule),
                  unavailableMetricIDs.contains(dependency)
            else { return nil }
            return rule.condition
        }.sorted()
        if !skippedConditions.isEmpty {
            onDiagnostic(
                "Unavailable conditions skipped: "
                    + skippedConditions.joined(separator: ", ")
            )
        }

        thresholdMonitor.onConditionUpdate = { [weak self] update in
            self?.emit(update)
        }
        systemMonitor.onConditionUpdate = { [weak self] update in
            self?.emit(update)
        }
        thermalMonitor.onConditionUpdate = { [weak self] update in
            self?.emit(update)
        }

        if !availableProviders.isEmpty {
            engine.register(availableProviders, alreadyFiltered: true)
            engine.setActiveMetrics(availableMetricIDs)
            engine.onCycleReport = { [weak self] report in
                self?.received(report)
            }
            engine.start(onBattery: currentPowerState)
        }

        let initialCoverage = coverage(at: Date())
        lastCoverage = initialCoverage
        if heartbeatInterval != nil {
            onRecord(.ready(initialCoverage))
        }

        evaluateThermal(at: Date())
        startSamplingClock()
        startHeartbeatClock()
    }

    func runUntilCancelled() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(3_600))
        }
        stop()
    }

    func stop() {
        samplingTask?.cancel()
        heartbeatTask?.cancel()
        samplingTask = nil
        heartbeatTask = nil
        engine.stop()
    }

    private func received(_ report: SamplingCycleReport) {
        for (metric, sample) in report.samples {
            latest[metric] = sample
            consecutiveFailures[metric] = 0
        }
        for metric in report.failedMetricIDs {
            consecutiveFailures[metric, default: 0] += 1
        }
        let now = Date()
        evaluateProviderBacked(at: now)
        publishCoverageChange(at: now)
    }

    private func evaluateProviderBacked(at now: Date) {
        let fresh = latest.filter { metric, sample in
            consecutiveFailures[metric, default: 0] == 0
                && now.timeIntervalSince(sample.timestamp) <= staleAfter
        }
        thresholdMonitor.evaluate(
            latest: fresh,
            rules: configuration.thresholdRules,
            now: now
        )
        systemMonitor.evaluate(
            readings: SystemConditionSource.readings(latest: fresh),
            rules: configuration.systemRules.filter {
                $0.key != .thermalPressure
            },
            now: now
        )
    }

    private func evaluateThermal(at now: Date) {
        guard let rule = configuration.systemRules[.thermalPressure],
              rule.enabled
        else { return }
        thermalMonitor.evaluate(
            readings: SystemConditionSource.readings(latest: [:]),
            rules: [.thermalPressure: rule],
            now: now
        )
    }

    private func startSamplingClock() {
        samplingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                let onBattery = SystemPowerSource.isOnBattery
                if onBattery != currentPowerState {
                    currentPowerState = onBattery
                    engine.updatePowerState(onBattery: onBattery)
                }
                let now = Date()
                evaluateThermal(at: now)
                publishCoverageChange(at: now)
            }
        }
    }

    private func startHeartbeatClock() {
        guard let heartbeatInterval else { return }
        heartbeatTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: heartbeatInterval)
                guard !Task.isCancelled, let self else { return }
                onRecord(.heartbeat(coverage(at: Date())))
            }
        }
    }

    private func publishCoverageChange(at now: Date) {
        let current = coverage(at: now)
        guard current != lastCoverage else { return }
        let prior = lastCoverage
        lastCoverage = current
        if heartbeatInterval != nil {
            onRecord(.status(current, timestamp: now))
        } else if current.status != prior?.status {
            onDiagnostic(coverageDescription(current))
        }
    }

    private func coverage(at now: Date) -> WatchCoverageSnapshot {
        var unavailableConditions: Set<String> = []
        var collectingConditions: Set<String> = []
        var staleMetrics: Set<MetricID> = []

        for rule in configuredRules {
            guard let dependency = samplingMetricID(for: rule) else { continue }
            if unavailableMetricIDs.contains(dependency)
                || consecutiveFailures[dependency, default: 0] >= 3 {
                unavailableConditions.insert(rule.condition)
                continue
            }
            guard let sample = latest[dependency] else {
                collectingConditions.insert(rule.condition)
                continue
            }
            if now.timeIntervalSince(sample.timestamp) > staleAfter {
                staleMetrics.insert(dependency)
            }
        }

        let status: WatchCoverageStatus
        if !unavailableConditions.isEmpty || !staleMetrics.isEmpty {
            status = .degraded
        } else if !collectingConditions.isEmpty {
            status = .collecting
        } else {
            status = .healthy
        }
        return WatchCoverageSnapshot(
            status: status,
            watchedConditions: configuredRules.map(\.condition).filter {
                !unavailableConditions.contains($0)
            }.sorted(),
            unavailableConditions: unavailableConditions.sorted(),
            collectingConditions: collectingConditions.sorted(),
            staleMetrics: staleMetrics.sorted { $0.rawValue < $1.rawValue },
            lastSampleAt: latest.values.map(\.timestamp).max()
        )
    }

    private func emit(_ update: AlertConditionUpdate) {
        guard update.transition != .pending else { return }
        let event = AlertStreamEvent(update: update)
        if heartbeatInterval == nil {
            onLegacyEvent(event)
        } else {
            onRecord(.alert(event))
        }
    }

    private func samplingMetricID(for rule: ConfiguredAlertRule) -> MetricID? {
        if rule.condition == SystemAlertSignal.thermalPressure.conditionKey {
            return nil
        }
        return rule.metric
    }

    private func coverageDescription(_ coverage: WatchCoverageSnapshot) -> String {
        switch coverage.status {
        case .healthy:
            return "Alert sampling coverage restored."
        case .collecting:
            return "Alert sampling is collecting initial readings."
        case .degraded:
            let affected = coverage.unavailableConditions
                + coverage.staleMetrics.map(\.rawValue)
            return "Alert sampling coverage degraded: "
                + affected.joined(separator: ", ")
        }
    }
}
