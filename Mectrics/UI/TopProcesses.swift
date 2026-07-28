import AppKit
import SwiftUI

/// One row of the "top processes" list.
struct TopProcessEntry: Identifiable, Equatable {
    let pid: Int
    let name: String
    /// %CPU for the CPU list, resident MB for the memory list.
    let value: Double

    var id: Int { pid }
}

/// Samples the heaviest processes on demand via `/bin/ps` (spawned only while a
/// popover with the list is open — not part of the periodic engine sampling).
enum TopProcesses {
    enum Mode {
        case cpu, memory
    }

    static func sample(_ mode: Mode, limit: Int = 6) async -> [TopProcessEntry] {
        let sortFlag = mode == .cpu ? "-r" : "-m"
        let column = mode == .cpu ? "pcpu" : "rss"
        guard let output = await run("/bin/ps", ["-Aceo", "pid=,\(column)=,comm=", sortFlag])
        else { return [] }

        return output.split(separator: "\n").prefix(limit).compactMap { line in
            let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count == 3,
                  let pid = Int(parts[0]),
                  let raw = Double(parts[1])
            else { return nil }
            let name = String(parts[2])
            // rss is KB → MB for display.
            let value = mode == .cpu ? raw : raw / 1024
            return TopProcessEntry(pid: pid, name: name, value: value)
        }
    }

    static func openActivityMonitor() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private static func run(_ path: String, _ arguments: [String]) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = arguments
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = Pipe()
                do {
                    try process.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    continuation.resume(returning: String(data: data, encoding: .utf8))
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

/// Collapsible "Top processes" section for the CPU/Memory popovers. Rows are live
/// (refreshed while open); clicking any row opens Activity Monitor.
struct TopProcessesView: View {
    let mode: TopProcesses.Mode
    var accent: Color

    @AppStorage("topProcessesExpanded") private var expanded = true
    @State private var entries: [TopProcessEntry] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.small) {
            // Custom collapsible header — DisclosureGroup's built-in chevron collides
            // with its label in this narrow layout.
            Button {
                withAnimation(ExperienceMotion.stateChange(reduceMotion: reduceMotion)) {
                    expanded.toggle()
                }
            } label: {
                HStack(spacing: ExperienceSpacing.xSmall) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                    Text("Top processes")
                        .font(.callout)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(String(
                localized: "topProcs.toggle.help",
                defaultValue: "Show or hide the process list"
            ))

            if expanded {
                VStack(alignment: .leading, spacing: ExperienceSpacing.xSmall) {
                    ForEach(entries) { entry in
                        Button {
                            TopProcesses.openActivityMonitor()
                        } label: {
                            HStack {
                                Text(entry.name)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Spacer(minLength: ExperienceSpacing.medium)
                                Text(mode == .cpu
                                     ? String(format: "%.1f%%", entry.value)
                                     : String(format: "%.0f MB", entry.value))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .help(String(localized: "topProcs.open", defaultValue: "Open Activity Monitor"))
                    }
                }
            }
        }
        .task(id: expanded) {
            guard expanded else { return }
            while !Task.isCancelled {
                let fresh = await TopProcesses.sample(mode)
                if !fresh.isEmpty { entries = fresh }
                try? await Task.sleep(for: .seconds(4))
            }
        }
    }
}
