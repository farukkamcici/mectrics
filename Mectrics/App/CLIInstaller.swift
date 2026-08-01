import AppKit
import Foundation

enum CLIInstallationState: Equatable {
    case notInstalled
    case installed
    case repairable
    case conflict
}

enum CLIInstallationResult: Equatable {
    case success
    case conflict
    case failed
}

/// Installs a machine-wide command that points back to the CLI inside Mectrics.app.
///
/// A symbolic link keeps the command on the same version as the app and avoids
/// downloading or maintaining a second executable.
enum CLIInstaller {
    static let installationURL = URL(filePath: "/usr/local/bin/mectrics")

    static var bundledCLIURL: URL {
        Bundle.main.bundleURL
            .appending(path: "Contents/Helpers/mectrics")
    }

    static func installationState(
        source: URL = bundledCLIURL,
        destination: URL = installationURL,
        fileManager: FileManager = .default
    ) -> CLIInstallationState {
        let destinationPath = destination.path(percentEncoded: false)
        guard let target = try? fileManager.destinationOfSymbolicLink(
            atPath: destinationPath
        ) else {
            return fileManager.fileExists(atPath: destinationPath)
                ? .conflict
                : .notInstalled
        }

        let resolved = resolvedTarget(target, for: destination)
        if resolved.standardizedFileURL == source.standardizedFileURL {
            return .installed
        }
        return isManagedCLIPath(resolved)
            ? .repairable
            : .conflict
    }

    @MainActor
    static func install(
        source: URL = bundledCLIURL,
        destination: URL = installationURL,
        fileManager: FileManager = .default
    ) -> CLIInstallationResult {
        guard fileManager.isExecutableFile(
            atPath: source.path(percentEncoded: false)
        ) else {
            return .failed
        }

        let existingTarget: String?
        switch installationState(
            source: source,
            destination: destination,
            fileManager: fileManager
        ) {
        case .installed:
            return .success
        case .conflict:
            return .conflict
        case .notInstalled:
            existingTarget = nil
        case .repairable:
            existingTarget = try? fileManager.destinationOfSymbolicLink(
                atPath: destination.path(percentEncoded: false)
            )
        }

        let command = installCommand(
            source: source,
            destination: destination,
            existingManagedTarget: existingTarget
        )
        guard runWithAdministratorPrivileges(command) else {
            return .failed
        }
        return installationState(
            source: source,
            destination: destination,
            fileManager: fileManager
        ) == .installed ? .success : .failed
    }

    @MainActor
    static func remove(
        source: URL = bundledCLIURL,
        destination: URL = installationURL,
        fileManager: FileManager = .default
    ) -> CLIInstallationResult {
        let state = installationState(
            source: source,
            destination: destination,
            fileManager: fileManager
        )
        guard state != .conflict else { return .conflict }
        guard state != .notInstalled else { return .success }
        guard let target = try? fileManager.destinationOfSymbolicLink(
            atPath: destination.path(percentEncoded: false)
        ) else {
            return .failed
        }

        let command = removeCommand(
            destination: destination,
            existingManagedTarget: target
        )
        guard runWithAdministratorPrivileges(command) else {
            return .failed
        }
        return installationState(
            source: source,
            destination: destination,
            fileManager: fileManager
        ) == .notInstalled ? .success : .failed
    }

    static func installCommand(
        source: URL,
        destination: URL,
        existingManagedTarget: String?
    ) -> String {
        let sourcePath = shellQuoted(source.path(percentEncoded: false))
        let destinationPath = shellQuoted(
            destination.path(percentEncoded: false)
        )
        let parentPath = shellQuoted(
            destination.deletingLastPathComponent().path(percentEncoded: false)
        )
        var commands: [String] = []
        if let existingManagedTarget {
            commands.append(
                "/bin/test \"$(/usr/bin/readlink \(destinationPath))\" = "
                    + shellQuoted(existingManagedTarget)
            )
            commands.append("/bin/rm -f \(destinationPath)")
        } else {
            commands.append("/bin/test ! -e \(destinationPath)")
            commands.append("/bin/test ! -L \(destinationPath)")
        }
        commands.append("/bin/mkdir -p \(parentPath)")
        commands.append("/bin/ln -s \(sourcePath) \(destinationPath)")
        return commands.joined(separator: " && ")
    }

    static func removeCommand(
        destination: URL,
        existingManagedTarget: String
    ) -> String {
        let destinationPath = shellQuoted(
            destination.path(percentEncoded: false)
        )
        return "/bin/test \"$(/usr/bin/readlink \(destinationPath))\" = "
            + shellQuoted(existingManagedTarget)
            + " && /bin/rm -f \(destinationPath)"
    }

    static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func resolvedTarget(
        _ target: String,
        for destination: URL
    ) -> URL {
        if target.hasPrefix("/") {
            return URL(filePath: target)
        }
        return destination.deletingLastPathComponent()
            .appending(path: target)
    }

    private static func isManagedCLIPath(_ url: URL) -> Bool {
        url.standardizedFileURL.path(percentEncoded: false)
            .hasSuffix("/Mectrics.app/Contents/Helpers/mectrics")
    }

    @MainActor
    private static func runWithAdministratorPrivileges(
        _ command: String
    ) -> Bool {
        let source = "do shell script \(appleScriptQuoted(command)) "
            + "with administrator privileges"
        guard let script = NSAppleScript(source: source) else { return false }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        return error == nil
    }

    private static func appleScriptQuoted(_ value: String) -> String {
        "\""
            + value
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            + "\""
    }
}
