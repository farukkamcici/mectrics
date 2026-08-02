import Foundation
import MetricsKit

struct AlertConfigurationStore {
    static let preferencesDomain = AlertConfigurationStorage.preferencesDomain
    static let thresholdRulesKey = AlertConfigurationStorage.thresholdRulesKey
    static let systemRulesKey = AlertConfigurationStorage.systemRulesKey

    static var activePreferencesDomain: String {
        #if DEBUG
        if let testDomain = ProcessInfo.processInfo.environment[
            "MECTRICS_CLI_TEST_PREFERENCES_DOMAIN"
        ], !testDomain.isEmpty {
            return testDomain
        }
        #endif
        return preferencesDomain
    }

    var defaults: UserDefaults

    init(defaults: UserDefaults? = nil) throws {
        guard let defaults = defaults ?? UserDefaults(
            suiteName: Self.activePreferencesDomain
        ) else {
            throw CLIExecutionError.unreadableConfiguration
        }
        self.defaults = defaults
    }

    func load() throws -> AlertConfiguration {
        let configuration: AlertConfiguration
        do {
            configuration = try AlertConfiguration.decode(
                thresholdData: defaults.data(forKey: Self.thresholdRulesKey),
                systemData: defaults.data(forKey: Self.systemRulesKey)
            )
        } catch {
            throw CLIExecutionError.unreadableConfiguration
        }
        try Self.validate(configuration)
        return configuration
    }

    static func validate(_ configuration: AlertConfiguration) throws {
        for (metric, rule) in configuration.thresholdRules where rule.enabled {
            let allowedThreshold = metric == .sensors
                ? 1...125
                : 0...100
            guard allowedThreshold.contains(rule.thresholdPercent) else {
                throw CLIExecutionError.invalidConfiguration(
                    "\(metric.rawValue) has an out-of-range threshold"
                )
            }
            try validateTiming(
                duration: rule.durationSeconds,
                cooldown: rule.cooldownSeconds,
                condition: "threshold.\(metric.rawValue)"
            )
        }

        for (signal, rule) in configuration.systemRules where rule.enabled {
            guard rule.thresholdValue.isFinite else {
                throw CLIExecutionError.invalidConfiguration(
                    "\(signal.conditionKey) has a non-finite threshold"
                )
            }
            let thresholdIsValid: Bool
            switch signal {
            case .thermalPressure:
                thresholdIsValid = (0...3).contains(rule.thresholdValue)
            case .memoryPressure:
                thresholdIsValid = [1.0, 2.0, 4.0].contains(rule.thresholdValue)
            case .diskAvailableCapacity:
                thresholdIsValid = rule.thresholdValue >= 0
            case .batteryService:
                thresholdIsValid = (0...1).contains(rule.thresholdValue)
            }
            guard thresholdIsValid else {
                throw CLIExecutionError.invalidConfiguration(
                    "\(signal.conditionKey) has an out-of-range threshold"
                )
            }
            try validateTiming(
                duration: rule.durationSeconds,
                cooldown: rule.cooldownSeconds,
                condition: signal.conditionKey
            )
        }
    }

    private static func validateTiming(
        duration: Int,
        cooldown: Int,
        condition: String
    ) throws {
        guard (0...86_400).contains(duration),
              (0...604_800).contains(cooldown)
        else {
            throw CLIExecutionError.invalidConfiguration(
                "\(condition) has an out-of-range duration or cooldown"
            )
        }
    }
}
