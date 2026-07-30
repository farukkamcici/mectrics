import AppKit
import Foundation
import MetricsKit
import Observation
import Security
import SwiftUI
import UniformTypeIdentifiers

enum DiagnosticsSection: String, CaseIterable, Identifiable {
    case systemSummary
    case applicationLog
    case providers
    case alertConfiguration
    case widget
    case attentionLog

    var id: String { rawValue }

    var localizedName: String {
        localizedName()
    }

    func localizedName(locale: Locale? = nil) -> String {
        switch self {
        case .systemSummary:
            return String(
                localized: "diagnostics.section.summary",
                defaultValue: "System Summary",
                bundle: AppLocalization.bundle(for: locale),
                locale: locale ?? .current
            )
        case .applicationLog:
            return String(
                localized: "diagnostics.section.log",
                defaultValue: "Application Log",
                bundle: AppLocalization.bundle(for: locale),
                locale: locale ?? .current
            )
        case .providers:
            return String(
                localized: "diagnostics.section.providers",
                defaultValue: "Provider Status",
                bundle: AppLocalization.bundle(for: locale),
                locale: locale ?? .current
            )
        case .alertConfiguration:
            return String(
                localized: "diagnostics.section.alerts",
                defaultValue: "Alert Configuration",
                bundle: AppLocalization.bundle(for: locale),
                locale: locale ?? .current
            )
        case .widget:
            return String(
                localized: "diagnostics.section.widget",
                defaultValue: "Widget Status",
                bundle: AppLocalization.bundle(for: locale),
                locale: locale ?? .current
            )
        case .attentionLog:
            return String(
                localized: "diagnostics.section.attention",
                defaultValue: "Recent Attention Log",
                bundle: AppLocalization.bundle(for: locale),
                locale: locale ?? .current
            )
        }
    }
}

enum DiagnosticFactState: String, Equatable {
    case yes
    case no
    case unknown
}

enum DiagnosticLogCode: String, Codable {
    case appLaunched
    case samplingStarted
    case powerSourceChanged
}

struct DiagnosticLogEntry: Codable, Equatable {
    let timestamp: Date
    let code: DiagnosticLogCode
}

private struct DiagnosticLogArchive: Codable {
    let schemaVersion: Int
    let entries: [DiagnosticLogEntry]
}

/// A small allowlisted operational log. Callers can record only known event codes,
/// so names, paths, addresses, and arbitrary error payloads cannot enter the archive.
@MainActor
final class DiagnosticLogStore {
    static let shared = DiagnosticLogStore()

    private(set) var entries: [DiagnosticLogEntry]
    private let fileURL: URL
    private let now: () -> Date
    private let capacity: Int
    private let retention: TimeInterval

    init(
        fileURL: URL? = nil,
        capacity: Int = 200,
        retention: TimeInterval = 7 * 24 * 60 * 60,
        now: @escaping () -> Date = Date.init
    ) {
        self.fileURL = fileURL ?? Self.defaultFileURL
        self.capacity = capacity
        self.retention = retention
        self.now = now
        entries = Self.load(from: self.fileURL)
        prune()
    }

    func record(_ code: DiagnosticLogCode) {
        entries.append(DiagnosticLogEntry(timestamp: now(), code: code))
        prune()
        persist()
    }

    private func prune() {
        let cutoff = now().addingTimeInterval(-retention)
        entries.removeAll { $0.timestamp < cutoff }
        entries.sort { $0.timestamp < $1.timestamp }
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
        }
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .millisecondsSince1970
            let archive = DiagnosticLogArchive(
                schemaVersion: 1,
                entries: entries
            )
            try encoder.encode(archive).write(to: fileURL, options: .atomic)
        } catch {
            // Diagnostics must never destabilize monitoring.
        }
    }

    private static func load(from url: URL) -> [DiagnosticLogEntry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return (
            try? decoder.decode(
                DiagnosticLogArchive.self,
                from: data
            ).entries
        ) ?? []
    }

    private static let defaultFileURL = FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
    )[0]
    .appendingPathComponent("Mectrics", isDirectory: true)
    .appendingPathComponent("diagnostic-log.json")
}

struct ProviderDiagnostic: Equatable {
    let metricID: MetricID
    let available: Bool
    let state: MetricDataState
    let consecutiveFailures: Int
}

struct AlertConfigurationDiagnostic: Equatable {
    let conditionKey: String
    let enabled: Bool
    let threshold: Double
    let durationSeconds: Int
    let cooldownSeconds: Int
    let destinations: [String]
}

struct WidgetDiagnosticFacts: Equatable {
    let embedded: DiagnosticFactState
    let signed: DiagnosticFactState
    let registered: DiagnosticFactState
    let galleryVisible: DiagnosticFactState
    let snapshotReadable: DiagnosticFactState
}

struct DiagnosticsInput: Equatable {
    let generatedAt: Date
    let systemSummary: SystemSummaryInput
    let applicationLog: [DiagnosticLogEntry]
    let providers: [ProviderDiagnostic]
    let alertConfigurations: [AlertConfigurationDiagnostic]
    let widget: WidgetDiagnosticFacts
    let attentionLog: String
}

enum DiagnosticsBuilder {
    static let schema = "mectrics.diagnostics.v1"
    static let defaultSections = Set(
        DiagnosticsSection.allCases.filter { $0 != .attentionLog }
    )

    @MainActor
    static func capture(
        model: AppModel,
        diagnosticLog: DiagnosticLogStore? = nil,
        generatedAt: Date = Date()
    ) -> DiagnosticsInput {
        let diagnosticLog = diagnosticLog ?? .shared
        let allMetricIDs = Set(model.availableModules)
            .union(model.enabledModules)
            .sorted { $0.rawValue < $1.rawValue }
        let providers = allMetricIDs.map { id in
            ProviderDiagnostic(
                metricID: id,
                available: model.availableModules.contains(id),
                state: model.metricState(
                    for: id,
                    isEnabled: model.enabledModules.contains(id)
                ),
                consecutiveFailures:
                    model.consecutiveSamplingFailures[id] ?? 0
            )
        }
        let thresholdRules = model.alertRules.map { id, rule in
            AlertConfigurationDiagnostic(
                conditionKey: "threshold.\(id.rawValue)",
                enabled: rule.enabled,
                threshold: Double(rule.thresholdPercent),
                durationSeconds: rule.durationSeconds,
                cooldownSeconds: rule.cooldownSeconds,
                destinations: rule.destinations.map(\.rawValue).sorted()
            )
        }
        let systemRules = model.systemAlertRules.map { signal, rule in
            AlertConfigurationDiagnostic(
                conditionKey: signal.conditionKey,
                enabled: rule.enabled,
                threshold: rule.thresholdValue,
                durationSeconds: rule.durationSeconds,
                cooldownSeconds: rule.cooldownSeconds,
                destinations: rule.destinations.map(\.rawValue).sorted()
            )
        }
        return DiagnosticsInput(
            generatedAt: generatedAt,
            systemSummary: SystemSummaryBuilder.capture(model: model),
            applicationLog: diagnosticLog.entries,
            providers: providers,
            alertConfigurations: (thresholdRules + systemRules).sorted {
                $0.conditionKey < $1.conditionKey
            },
            widget: captureWidgetFacts(),
            attentionLog: model.attentionLog.exportText(
                generatedAt: generatedAt
            )
        )
    }

    static func render(
        _ input: DiagnosticsInput,
        sections: Set<DiagnosticsSection>,
        locale: Locale? = nil
    ) -> String {
        var output = [
            String(
                localized: "diagnostics.export.title",
                defaultValue: "Mectrics Diagnostics",
                bundle: AppLocalization.bundle(for: locale),
                locale: locale ?? .current
            ),
            "Schema: \(schema)",
            "Generated: \(iso8601.string(from: input.generatedAt))"
        ].joined(separator: "\n") + "\n"

        for section in DiagnosticsSection.allCases where sections.contains(section) {
            output += "\n## \(section.localizedName(locale: locale))\n"
            switch section {
            case .systemSummary:
                output += SystemSummaryBuilder.render(
                    input.systemSummary,
                    locale: locale
                )
            case .applicationLog:
                output += renderLog(input.applicationLog)
            case .providers:
                output += renderProviders(input.providers)
            case .alertConfiguration:
                output += renderAlerts(input.alertConfigurations)
            case .widget:
                output += renderWidget(input.widget)
            case .attentionLog:
                output += input.attentionLog
            }
        }
        return DiagnosticsRedactor.redact(output)
    }

    private static func renderLog(_ entries: [DiagnosticLogEntry]) -> String {
        guard !entries.isEmpty else { return "- none\n" }
        return entries.map {
            "- \(iso8601.string(from: $0.timestamp)) | \($0.code.rawValue)"
        }.joined(separator: "\n") + "\n"
    }

    private static func renderProviders(
        _ providers: [ProviderDiagnostic]
    ) -> String {
        guard !providers.isEmpty else { return "- none\n" }
        return providers.map {
            "- \($0.metricID.rawValue) | available=\($0.available) | state=\($0.state.rawValue) | consecutiveFailures=\($0.consecutiveFailures)"
        }.joined(separator: "\n") + "\n"
    }

    private static func renderAlerts(
        _ configurations: [AlertConfigurationDiagnostic]
    ) -> String {
        guard !configurations.isEmpty else { return "- none\n" }
        return configurations.map {
            let destinations = $0.destinations.joined(separator: ",")
            return "- \($0.conditionKey) | enabled=\($0.enabled) | threshold=\(number($0.threshold)) | duration=\($0.durationSeconds) | cooldown=\($0.cooldownSeconds) | destinations=\(destinations)"
        }.joined(separator: "\n") + "\n"
    }

    private static func renderWidget(_ facts: WidgetDiagnosticFacts) -> String {
        [
            "Embedded: \(facts.embedded.rawValue)",
            "Signed: \(facts.signed.rawValue)",
            "Registered: \(facts.registered.rawValue)",
            "Gallery visible: \(facts.galleryVisible.rawValue)",
            "Snapshot readable: \(facts.snapshotReadable.rawValue)",
            "Note: registration and gallery visibility are system-managed and are reported as unknown when no public in-app status is available."
        ].joined(separator: "\n") + "\n"
    }

    @MainActor
    private static func captureWidgetFacts() -> WidgetDiagnosticFacts {
        let extensionURL = Bundle.main.builtInPlugInsURL?
            .appendingPathComponent("MectricsWidget.appex")
        let embedded = extensionURL.map {
            FileManager.default.fileExists(atPath: $0.path)
        } ?? false
        let signed: DiagnosticFactState
        if let extensionURL, embedded {
            signed = signatureIsValid(at: extensionURL) ? .yes : .no
        } else {
            signed = .unknown
        }
        let snapshotReadable: DiagnosticFactState
        do {
            _ = try SharedMetricSnapshotStore().read()
            snapshotReadable = .yes
        } catch {
            snapshotReadable = .no
        }
        return WidgetDiagnosticFacts(
            embedded: embedded ? .yes : .no,
            signed: signed,
            registered: .unknown,
            galleryVisible: .unknown,
            snapshotReadable: snapshotReadable
        )
    }

    private static func signatureIsValid(at url: URL) -> Bool {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(
            url as CFURL,
            [],
            &staticCode
        ) == errSecSuccess, let staticCode else {
            return false
        }
        return SecStaticCodeCheckValidity(staticCode, [], nil) == errSecSuccess
    }

    private static func number(_ value: Double) -> String {
        String(
            format: "%.2f",
            locale: Locale(identifier: "en_US_POSIX"),
            value
        )
    }

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

enum DiagnosticsRedactor {
    private static let rules: [(String, String)] = [
        (
            #"(?i)\b(user|username|host|hostname|serial(?: number)?|process|ip(?: address)?|mac(?: address)?|wi-fi(?: name)?|bluetooth(?: name)?)\s*[:=]\s*[^\n]+"#,
            "$1: <redacted>"
        ),
        (
            #"/(?:Users|home)/[^/\s]+(?:/[^\s\n]*)?"#,
            "<redacted-path>"
        ),
        (
            #"\b(?:\d{1,3}\.){3}\d{1,3}\b"#,
            "<redacted-address>"
        ),
        (
            #"(?i)\b(?:[0-9a-f]{2}:){5}[0-9a-f]{2}\b"#,
            "<redacted-address>"
        ),
        (
            #"(?i)\b[a-z0-9][a-z0-9-]{0,62}\.local\b"#,
            "<redacted-host>"
        )
    ]

    static func redact(_ text: String) -> String {
        rules.reduce(text) { result, rule in
            guard let expression = try? NSRegularExpression(
                pattern: rule.0
            ) else {
                return result
            }
            let range = NSRange(
                result.startIndex..<result.endIndex,
                in: result
            )
            return expression.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: rule.1
            )
        }
    }
}

@MainActor
final class DiagnosticsWindowController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private let onClose: () -> Void
    private var window: NSWindow?

    init(model: AppModel, onClose: @escaping () -> Void = {}) {
        self.model = model
        self.onClose = onClose
        super.init()
    }

    func show() {
        NSApp.setActivationPolicy(.regular)
        if window == nil {
            window = makeWindow()
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.clearInitialFocus()
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }

    private func makeWindow() -> NSWindow {
        let input = DiagnosticsBuilder.capture(model: model)
        let host = NSHostingController(
            rootView: DiagnosticsView(input: input).quietFocusRing()
        )
        host.sizingOptions = []
        let window = NSWindow(contentViewController: host)
        window.title = String(
            localized: "diagnostics.window.title",
            defaultValue: "Mectrics Diagnostics"
        )
        window.styleMask = [
            .titled, .closable, .miniaturizable, .resizable
        ]
        window.setContentSize(NSSize(width: 820, height: 620))
        window.minSize = NSSize(width: 680, height: 480)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }
}

private struct DiagnosticsView: View {
    let input: DiagnosticsInput
    @State private var sections = DiagnosticsBuilder.defaultSections
    @State private var saveFailed = false

    private var preview: String {
        DiagnosticsBuilder.render(input, sections: sections)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.medium) {
            Text("Select the sections to include, then review the exact local export.")
                .foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: ExperienceSpacing.large) {
                VStack(alignment: .leading, spacing: ExperienceSpacing.small) {
                    ForEach(DiagnosticsSection.allCases) { section in
                        Toggle(
                            section.localizedName,
                            isOn: binding(for: section)
                        )
                        .toggleStyle(.checkbox)
                    }
                    Divider()
                    Label(
                        "Nothing is uploaded automatically.",
                        systemImage: "lock.shield"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .frame(width: 210, alignment: .leading)

                TextEditor(text: .constant(preview))
                    .font(.system(.body, design: .monospaced))
                    .accessibilityLabel("Diagnostics preview")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .border(.separator)
            }
            HStack {
                if saveFailed {
                    Text("The diagnostics file could not be saved.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Save Diagnostics…") {
                    save(preview)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(ExperienceSpacing.large)
    }

    private func binding(for section: DiagnosticsSection) -> Binding<Bool> {
        Binding(
            get: { sections.contains(section) },
            set: { selected in
                if selected {
                    sections.insert(section)
                } else {
                    sections.remove(section)
                }
            }
        )
    }

    private func save(_ text: String) {
        let panel = NSSavePanel()
        panel.title = String(
            localized: "diagnostics.save.title",
            defaultValue: "Save Mectrics Diagnostics"
        )
        panel.nameFieldStringValue = "mectrics-diagnostics.txt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Data(text.utf8).write(to: url, options: .atomic)
            saveFailed = false
        } catch {
            saveFailed = true
        }
    }
}
