import ArgumentParser

@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
public struct MectricsCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "mectrics",
        abstract: "Read-only automation for Mectrics alert rules and metrics.",
        discussion: """
            Configure alert rules in Mectrics.app. The CLI never changes settings.
            Run it as the same macOS user who configured the app.
            """,
        version: "mectrics \(InstalledVersion.current)",
        subcommands: [
            AlertsCommand.self,
            CheckCLICommand.self,
            SnapshotCLICommand.self,
            DoctorCLICommand.self,
            VersionCLICommand.self
        ]
    )

    public init() {}
}

public struct AlertsCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "alerts",
        abstract: "List or stream enabled alert rules.",
        subcommands: [AlertsListCLICommand.self, AlertsWatchCLICommand.self]
    )

    public init() {}
}

public struct CheckCLICommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "check",
        abstract: "Check every enabled alert rule once."
    )

    @Flag(help: "Write a versioned JSON report to standard output.")
    public var json = false

    public init() {}

    public mutating func run() async throws {
        try await executeCLI {
            try await CLIApplication.live.check(json: json)
        }
    }
}

public struct SnapshotCLICommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "snapshot",
        abstract: "Read every available metric once."
    )

    @Flag(help: "Write a versioned JSON report to standard output.")
    public var json = false

    public init() {}

    public mutating func run() async throws {
        try await executeCLI {
            try await CLIApplication.live.snapshot(json: json)
        }
    }
}

public struct AlertsListCLICommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List enabled alert rules."
    )

    @Flag(help: "Write a versioned JSON report to standard output.")
    public var json = false

    public init() {}

    public mutating func run() async throws {
        try await executeCLI {
            try await CLIApplication.live.listRules(json: json)
        }
    }
}

public struct AlertsWatchCLICommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "watch",
        abstract: "Stream alert activation and recovery events.",
        discussion: """
            Rules are loaded when the stream starts. Restart this command after changing
            alert rules in Mectrics.app.
            """
    )

    @Flag(help: "Write newline-delimited JSON to standard output.")
    public var json = false

    @Option(
        name: .long,
        help: "Emit tagged status and heartbeat records at this interval in seconds."
    )
    public var heartbeat: Int?

    public init() {}

    public mutating func validate() throws {
        if heartbeat != nil && !json {
            throw ValidationError("--heartbeat requires --json.")
        }
        if let heartbeat, !(5...3_600).contains(heartbeat) {
            throw ValidationError("--heartbeat must be between 5 and 3600 seconds.")
        }
    }

    public mutating func run() async throws {
        try await executeCLI {
            try await CLIApplication.live.watch(
                json: json,
                heartbeatSeconds: heartbeat
            )
        }
    }
}

public struct DoctorCLICommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Validate CLI configuration and alert coverage."
    )

    @Flag(help: "Write a versioned JSON report to standard output.")
    public var json = false

    public init() {}

    public mutating func run() async throws {
        try await executeCLI {
            try await CLIApplication.live.doctor(json: json)
        }
    }
}

public struct VersionCLICommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "version",
        abstract: "Show the installed Mectrics version."
    )

    public init() {}

    public mutating func run() async throws {
        try await executeCLI {
            await CLIApplication.live.showVersion()
        }
    }
}

private func executeCLI(
    _ operation: () async throws -> Int32
) async throws {
    do {
        try throwExitCode(try await operation())
    } catch let error as CLIExecutionError {
        CLIOutput.live.diagnostic(error.localizedDescription)
        throw ExitCode(error.exitCode)
    }
}
