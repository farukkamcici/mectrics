import Foundation

public enum AlertDestination: String, Codable, CaseIterable, Hashable, Sendable {
    case notification
    case compactHealth
    case attentionLog
}

public enum AlertConditionState: String, Codable, Equatable, Sendable {
    case normal
    case pending
    case active
}

public enum AlertConditionTransition: String, Codable, Equatable, Sendable {
    case pending
    case activated
    case recovered
}

public struct AlertConditionUpdate: Equatable, Sendable {
    public let conditionKey: String
    public let metricID: MetricID
    public let state: AlertConditionState
    public let transition: AlertConditionTransition
    public let measuredValue: Double
    public let unit: MetricUnit
    public let thresholdValue: Double
    public let durationSeconds: Int
    public let startedAt: Date?
    public let destinations: Set<AlertDestination>

    public init(
        conditionKey: String? = nil,
        metricID: MetricID,
        state: AlertConditionState,
        transition: AlertConditionTransition,
        measuredValue: Double,
        unit: MetricUnit? = nil,
        thresholdValue: Double,
        durationSeconds: Int,
        startedAt: Date?,
        destinations: Set<AlertDestination>
    ) {
        self.conditionKey = conditionKey ?? "threshold.\(metricID.rawValue)"
        self.metricID = metricID
        self.state = state
        self.transition = transition
        self.measuredValue = measuredValue
        self.unit = unit ?? (metricID == .sensors ? .celsius : .percent)
        self.thresholdValue = thresholdValue
        self.durationSeconds = durationSeconds
        self.startedAt = startedAt
        self.destinations = destinations
    }
}

/// One user-configurable threshold rule per metric. Battery fires below its
/// threshold; every other percentage rule fires above it.
public struct AlertRule: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var thresholdPercent: Int
    public var durationSeconds: Int
    public var cooldownSeconds: Int
    public var destinations: Set<AlertDestination>

    public init(
        enabled: Bool,
        thresholdPercent: Int,
        durationSeconds: Int = 30,
        cooldownSeconds: Int = 15 * 60,
        destinations: Set<AlertDestination> = [.attentionLog]
    ) {
        self.enabled = enabled
        self.thresholdPercent = thresholdPercent
        self.durationSeconds = durationSeconds
        self.cooldownSeconds = cooldownSeconds
        self.destinations = destinations
    }

    private enum CodingKeys: String, CodingKey {
        case enabled
        case thresholdPercent
        case durationSeconds
        case cooldownSeconds
        case destinations
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        thresholdPercent = try container.decode(Int.self, forKey: .thresholdPercent)
        durationSeconds = try container.decodeIfPresent(
            Int.self,
            forKey: .durationSeconds
        ) ?? 30
        cooldownSeconds = try container.decodeIfPresent(
            Int.self,
            forKey: .cooldownSeconds
        ) ?? 15 * 60

        if let decodedDestinations = try container.decodeIfPresent(
            Set<AlertDestination>.self,
            forKey: .destinations
        ) {
            destinations = decodedDestinations
        } else {
            destinations = enabled
                ? [.notification, .attentionLog]
                : [.attentionLog]
        }
    }
}

/// Conditions macOS reports directly rather than thresholds on a normalized sample.
///
/// These carry a judgement a raw number cannot: memory can sit at 90% with the kernel
/// under no pressure, and a CPU can read 85°C without the machine being slowed down.
/// The state itself is the thing worth alerting on.
public enum SystemAlertSignal: String, Codable, CaseIterable, Hashable, Sendable {
    case thermalPressure
    case memoryPressure
    case diskAvailableCapacity
    case batteryService

    /// The module this condition belongs to, for grouping and for opening the right
    /// detail window. Thermal pressure is reported for the whole chip; CPU is where a
    /// person looks for it, and the rule's own wording names the GPU too.
    public var metricID: MetricID {
        switch self {
        case .thermalPressure: return .cpu
        case .memoryPressure: return .memory
        case .diskAvailableCapacity: return .disk
        case .batteryService: return .battery
        }
    }

    /// The provider needed to read this condition, independent of the module used to
    /// present it. Thermal pressure comes directly from `ProcessInfo` and therefore
    /// has no sampling dependency.
    public var samplingMetricID: MetricID? {
        switch self {
        case .thermalPressure: return nil
        case .memoryPressure: return .memory
        case .diskAvailableCapacity: return .disk
        case .batteryService: return .battery
        }
    }

    public var unit: MetricUnit {
        switch self {
        case .diskAvailableCapacity: return .bytes
        case .thermalPressure, .memoryPressure, .batteryService: return .count
        }
    }

    public var conditionKey: String { "system.\(rawValue)" }
}

public struct SystemAlertRule: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var thresholdValue: Double
    public var durationSeconds: Int
    public var cooldownSeconds: Int
    public var destinations: Set<AlertDestination>

    public init(
        enabled: Bool,
        thresholdValue: Double,
        durationSeconds: Int = 30,
        cooldownSeconds: Int = 15 * 60,
        destinations: Set<AlertDestination> = [.attentionLog]
    ) {
        self.enabled = enabled
        self.thresholdValue = thresholdValue
        self.durationSeconds = durationSeconds
        self.cooldownSeconds = cooldownSeconds
        self.destinations = destinations
    }
}

public struct SystemConditionReading: Equatable, Sendable {
    public let signal: SystemAlertSignal
    public let value: Double

    public init(_ signal: SystemAlertSignal, value: Double) {
        self.signal = signal
        self.value = value
    }
}

public struct AlertConfiguration: Equatable, Sendable {
    public let thresholdRules: [MetricID: AlertRule]
    public let systemRules: [SystemAlertSignal: SystemAlertRule]

    public init(
        thresholdRules: [MetricID: AlertRule],
        systemRules: [SystemAlertSignal: SystemAlertRule]
    ) {
        self.thresholdRules = thresholdRules
        self.systemRules = systemRules
    }

    public var enabledRuleCount: Int {
        thresholdRules.values.filter(\.enabled).count
            + systemRules.values.filter(\.enabled).count
    }

    public var requiredMetricIDs: Set<MetricID> {
        let thresholdIDs = thresholdRules.compactMap { id, rule in
            rule.enabled ? id : nil
        }
        let systemIDs = systemRules.compactMap { signal, rule in
            rule.enabled ? signal.samplingMetricID : nil
        }
        return Set(thresholdIDs + systemIDs)
    }

    public static func decode(
        thresholdData: Data?,
        systemData: Data?,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> AlertConfiguration {
        let rawThresholds = try thresholdData.map {
            try decoder.decode([String: AlertRule].self, from: $0)
        } ?? [:]
        let rawSystemRules = try systemData.map {
            try decoder.decode([String: SystemAlertRule].self, from: $0)
        } ?? [:]

        return AlertConfiguration(
            thresholdRules: Dictionary(
                uniqueKeysWithValues: rawThresholds.compactMap { key, rule in
                    MetricID(rawValue: key).map { ($0, rule) }
                }
            ),
            systemRules: Dictionary(
                uniqueKeysWithValues: rawSystemRules.compactMap { key, rule in
                    SystemAlertSignal(rawValue: key).map { ($0, rule) }
                }
            )
        )
    }
}

public enum AlertComparison: String, Codable, Equatable, Sendable {
    case atOrAbove
    case atOrBelow
}

public struct ConfiguredAlertRule: Codable, Equatable, Sendable {
    public let condition: String
    public let metric: MetricID
    public let comparison: AlertComparison
    public let thresholdValue: Double
    public let unit: MetricUnit
    public let durationSeconds: Int
    public let cooldownSeconds: Int

    public init(metric: MetricID, rule: AlertRule) {
        condition = "threshold.\(metric.rawValue)"
        self.metric = metric
        comparison = metric == .battery ? .atOrBelow : .atOrAbove
        thresholdValue = Double(rule.thresholdPercent)
        unit = metric == .sensors ? .celsius : .percent
        durationSeconds = rule.durationSeconds
        cooldownSeconds = rule.cooldownSeconds
    }

    public init(signal: SystemAlertSignal, rule: SystemAlertRule) {
        condition = signal.conditionKey
        metric = signal.metricID
        comparison = signal == .diskAvailableCapacity ? .atOrBelow : .atOrAbove
        thresholdValue = rule.thresholdValue
        unit = signal.unit
        durationSeconds = rule.durationSeconds
        cooldownSeconds = rule.cooldownSeconds
    }
}

public struct AlertRuleList: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let timestamp: Date
    public let rules: [ConfiguredAlertRule]

    public init(
        configuration: AlertConfiguration,
        timestamp: Date = Date()
    ) {
        schemaVersion = 1
        self.timestamp = timestamp
        rules = configuration.configuredRules
    }
}

public enum AlertHealthStatus: String, Codable, Equatable, Sendable {
    case healthy
    case attention
    case unavailable
    case notConfigured
}

public enum AlertRuleCheckState: String, Codable, Equatable, Sendable {
    case normal
    case limitCrossed
    case unavailable
}

public struct AlertRuleCheck: Codable, Equatable, Sendable {
    public let condition: String
    public let metric: MetricID
    public let state: AlertRuleCheckState
    public let measuredValue: Double?
    public let unit: MetricUnit
    public let thresholdValue: Double
    public let comparison: AlertComparison

    public init(
        rule: ConfiguredAlertRule,
        state: AlertRuleCheckState,
        measuredValue: Double?
    ) {
        condition = rule.condition
        metric = rule.metric
        self.state = state
        self.measuredValue = measuredValue
        unit = rule.unit
        thresholdValue = rule.thresholdValue
        comparison = rule.comparison
    }
}

/// A one-shot check of the current readings against the configured limits.
///
/// Unlike the continuous monitors, this report does not wait for each rule's sustained
/// duration. A crossed limit means the rule would enter its pending state now.
public struct AlertHealthReport: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let timestamp: Date
    public let status: AlertHealthStatus
    public let conditions: [AlertRuleCheck]

    public init(
        configuration: AlertConfiguration,
        latest: [MetricID: MetricSample],
        timestamp: Date = Date()
    ) {
        schemaVersion = 1
        self.timestamp = timestamp
        conditions = configuration.configuredRules.map { rule in
            Self.check(rule, latest: latest)
        }
        if conditions.isEmpty {
            status = .notConfigured
        } else if conditions.contains(where: { $0.state == .limitCrossed }) {
            status = .attention
        } else if conditions.contains(where: { $0.state == .unavailable }) {
            status = .unavailable
        } else {
            status = .healthy
        }
    }

    private static func check(
        _ rule: ConfiguredAlertRule,
        latest: [MetricID: MetricSample]
    ) -> AlertRuleCheck {
        guard let measured = measure(rule, latest: latest) else {
            return AlertRuleCheck(
                rule: rule,
                state: .unavailable,
                measuredValue: nil
            )
        }
        let crossed = rule.comparison == .atOrBelow
            ? measured <= rule.thresholdValue
            : measured >= rule.thresholdValue
        return AlertRuleCheck(
            rule: rule,
            state: crossed ? .limitCrossed : .normal,
            measuredValue: measured
        )
    }

    private static func measure(
        _ rule: ConfiguredAlertRule,
        latest: [MetricID: MetricSample]
    ) -> Double? {
        // macOS reports the thermal state itself, so this condition is readable even
        // when no provider sampled successfully this cycle.
        if rule.condition == SystemAlertSignal.thermalPressure.conditionKey {
            return Double(ThermalPressureLevel.current.rawValue)
        }
        guard let sample = latest[rule.metric] else { return nil }
        switch rule.condition {
        case SystemAlertSignal.memoryPressure.conditionKey:
            return sample.detail["pressureLevel"]
        case SystemAlertSignal.diskAvailableCapacity.conditionKey:
            return sample.detail["free"]
        case SystemAlertSignal.batteryService.conditionKey:
            // No native service condition means macOS is not reporting a fault.
            return sample.detail["serviceRecommended"] ?? 0
        default:
            return sample.unit == .celsius
                ? sample.value
                : sample.value * 100
        }
    }
}

public extension AlertConfiguration {
    var configuredRules: [ConfiguredAlertRule] {
        let thresholds = thresholdRules.compactMap { metric, rule in
            rule.enabled ? ConfiguredAlertRule(metric: metric, rule: rule) : nil
        }
        let system = systemRules.compactMap { signal, rule in
            rule.enabled ? ConfiguredAlertRule(signal: signal, rule: rule) : nil
        }
        return (thresholds + system).sorted { $0.condition < $1.condition }
    }
}

/// Stable, versioned event written by the headless alert stream.
public struct AlertStreamEvent: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let timestamp: Date
    public let event: AlertConditionTransition
    public let condition: String
    public let metric: MetricID
    public let measuredValue: Double
    public let unit: MetricUnit
    public let thresholdValue: Double
    public let comparison: AlertComparison
    public let durationSeconds: Int
    public let startedAt: Date?

    public init(
        update: AlertConditionUpdate,
        timestamp: Date = Date()
    ) {
        schemaVersion = 1
        self.timestamp = timestamp
        event = update.transition
        condition = update.conditionKey
        metric = update.metricID
        measuredValue = update.measuredValue
        unit = update.unit
        thresholdValue = update.thresholdValue
        comparison = Self.comparison(for: update.conditionKey, metric: update.metricID)
        durationSeconds = update.durationSeconds
        startedAt = update.startedAt
    }

    private static func comparison(
        for condition: String,
        metric: MetricID
    ) -> AlertComparison {
        if condition == SystemAlertSignal.batteryService.conditionKey {
            return .atOrAbove
        }
        if metric == .battery
            || condition == SystemAlertSignal.diskAvailableCapacity.conditionKey {
            return .atOrBelow
        }
        return .atOrAbove
    }
}
