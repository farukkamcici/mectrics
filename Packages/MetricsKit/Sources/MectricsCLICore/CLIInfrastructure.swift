import ArgumentParser
import Darwin
import Foundation
import MetricsKit

enum CLIExit {
    static let healthy: Int32 = 0
    static let attention: Int32 = 1
    static let indeterminate: Int32 = 2
    static let usage: Int32 = EX_USAGE
    static let software: Int32 = EX_SOFTWARE
    static let configuration: Int32 = EX_CONFIG
}

enum CLIExecutionError: LocalizedError {
    case unreadableConfiguration
    case invalidConfiguration(String)
    case noEnabledRules
    case noCheckableRules
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .unreadableConfiguration:
            return "The saved Mectrics alert rules could not be read."
        case let .invalidConfiguration(reason):
            return "The saved Mectrics alert rules are invalid: \(reason)"
        case .noEnabledRules:
            return "No alert rules are enabled. Enable at least one in Mectrics Settings > Alerts."
        case .noCheckableRules:
            return "None of the enabled alert rules can be checked on this Mac."
        case .encodingFailed:
            return "Could not encode JSON output."
        }
    }

    var exitCode: Int32 {
        switch self {
        case .unreadableConfiguration, .invalidConfiguration:
            return CLIExit.configuration
        case .noEnabledRules, .noCheckableRules:
            return CLIExit.indeterminate
        case .encodingFailed:
            return CLIExit.software
        }
    }
}

struct CLIOutput: @unchecked Sendable {
    var standardOutput: (String) -> Void
    var standardError: (String) -> Void

    static let live = CLIOutput(
        standardOutput: { message in
            FileHandle.standardOutput.write(Data(message.utf8))
        },
        standardError: { message in
            FileHandle.standardError.write(Data(message.utf8))
        }
    )

    func print(_ message: String) {
        standardOutput(message + "\n")
    }

    func diagnostic(_ message: String) {
        standardError(message + "\n")
    }
}

enum CLIJSON {
    static func encode<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data: Data
        do {
            data = try encoder.encode(value)
        } catch {
            throw CLIExecutionError.encodingFailed
        }
        guard let output = String(data: data, encoding: .utf8) else {
            throw CLIExecutionError.encodingFailed
        }
        return output
    }
}

enum InstalledVersion {
    static var current: String {
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
}

func throwExitCode(_ code: Int32) throws {
    guard code != CLIExit.healthy else { return }
    throw ExitCode(code)
}
