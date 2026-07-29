import AppKit
import MetricsKit
import SwiftUI

@MainActor
final class AttentionLogWindowController: NSObject, NSWindowDelegate {
    private let store: AttentionLogStore
    private let onClose: () -> Void
    private var window: NSWindow?

    init(store: AttentionLogStore, onClose: @escaping () -> Void = {}) {
        self.store = store
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
        let host = NSHostingController(rootView: AttentionLogView(store: store))
        host.sizingOptions = []
        let window = NSWindow(contentViewController: host)
        window.title = String(
            localized: "attention.title",
            defaultValue: "Attention Log"
        )
        window.styleMask = [.titled, .closable, .resizable]
        window.contentMinSize = NSSize(width: 540, height: 380)
        window.setContentSize(NSSize(width: 680, height: 520))
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setFrameAutosaveName("mectrics.attentionLog")
        if !window.setFrameUsingName("mectrics.attentionLog") {
            window.center()
        }
        return window
    }
}

private struct AttentionLogView: View {
    @Bindable var store: AttentionLogStore
    @State private var showingClearConfirmation = false
    @State private var exportPreview: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Meaningful local alert events from the last 30 days.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Export…") {
                    exportPreview = store.exportText()
                }
                .disabled(store.events.isEmpty)
                Button("Clear Log", role: .destructive) {
                    showingClearConfirmation = true
                }
                .disabled(store.events.isEmpty)
            }
            .padding()
            Divider()
            if store.events.isEmpty {
                ContentUnavailableView {
                    Label("No attention events", systemImage: "checkmark.circle")
                } description: {
                    Text("Mectrics records only meaningful local alert and recovery events.")
                }
            } else {
                List {
                    if !store.unresolvedEvents.isEmpty {
                        Section("Needs attention") {
                            ForEach(store.unresolvedEvents) { event in
                                eventRow(event)
                            }
                        }
                    }
                    ForEach(dayGroups, id: \.day) { group in
                        Section(group.day.formatted(date: .abbreviated, time: .omitted)) {
                            ForEach(group.events) { event in
                                eventRow(event)
                            }
                        }
                    }
                }
            }
        }
        .alert(
            "Clear Attention Log?",
            isPresented: $showingClearConfirmation
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Clear Log", role: .destructive) { store.clear() }
        } message: {
            Text("Alert rules and metric history will not change.")
        }
        .sheet(isPresented: Binding(
            get: { exportPreview != nil },
            set: { if !$0 { exportPreview = nil } }
        )) {
            exportPreviewSheet
        }
    }

    private var dayGroups: [(day: Date, events: [AttentionEvent])] {
        let calendar = Calendar.autoupdatingCurrent
        let grouped = Dictionary(grouping: store.resolvedEvents) {
            calendar.startOfDay(for: $0.startedAt)
        }
        return grouped
            .map { (day: $0.key, events: $0.value) }
            .sorted { $0.day > $1.day }
    }

    private func eventRow(_ event: AttentionEvent) -> some View {
        HStack(alignment: .top, spacing: ExperienceSpacing.small) {
            Image(systemName: event.isResolved
                  ? "checkmark.circle"
                  : "exclamationmark.triangle.fill")
                .foregroundStyle(
                    event.isResolved ? Color.secondary : Color.orange
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: ExperienceSpacing.xSmall) {
                HStack {
                    Text(eventTitle(event))
                        .font(.headline)
                    Text(event.state.localizedAttentionName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(event.startedAt, style: .time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(triggerSummary(event))
                    .font(.callout)
                Text(durationSummary(event))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(eventTitle(event))
        .accessibilityValue(
            "\(event.severity.localizedName), \(event.state.localizedAttentionName), \(triggerSummary(event)), \(durationSummary(event))"
        )
    }

    private func triggerSummary(_ event: AttentionEvent) -> String {
        switch event.conditionKey {
        case "system.energyGuard":
            return String(
                localized: "attention.trigger.energyGuard",
                defaultValue: "Monitoring changed to \(energyGuardMode(event.observedValue).localizedName) to reduce Mectrics energy use"
            )
        case SystemAlertSignal.diskAvailableCapacity.conditionKey:
            return String(
                localized: "attention.trigger.diskCapacity",
                defaultValue: "Available disk space fell below \(MetricFormat.bytes(event.thresholdValue)) for \(event.durationSeconds) seconds"
            )
        case SystemAlertSignal.batteryService.conditionKey:
            return String(
                localized: "attention.trigger.batteryService",
                defaultValue: "macOS reported that battery service is recommended"
            )
        default:
            break
        }
        let comparison = event.metricID == .battery
            ? String(localized: "attention.trigger.below", defaultValue: "below")
            : String(localized: "attention.trigger.above", defaultValue: "above")
        let suffix = event.unit == .celsius ? "°C" : "%"
        let threshold = event.thresholdValue.formatted(
            .number.precision(.fractionLength(0))
        )
        return String(
            localized: "attention.trigger.summary",
            defaultValue: "\(event.metricID.localizedName) \(comparison) \(threshold)\(suffix) for \(event.durationSeconds) seconds"
        )
    }

    private func eventTitle(_ event: AttentionEvent) -> String {
        if event.conditionKey == "system.energyGuard" {
            return String(
                localized: "attention.event.energyGuard",
                defaultValue: "Energy Guard"
            )
        }
        return event.metricID.localizedName
    }

    private func energyGuardMode(_ value: Double) -> EnergyGuardMode {
        switch Int(value) {
        case 1: return .reduced
        case 2...: return .protected
        default: return .normal
        }
    }

    private func durationSummary(_ event: AttentionEvent) -> String {
        guard let endedAt = event.endedAt else {
            return String(
                localized: "attention.duration.ongoing",
                defaultValue: "Ongoing since \(event.startedAt.formatted(date: .omitted, time: .shortened))"
            )
        }
        let duration = Duration.seconds(endedAt.timeIntervalSince(event.startedAt))
        return String(
            localized: "attention.duration.recovered",
            defaultValue: "Recovered after \(duration.formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated)))"
        )
    }

    private var exportPreviewSheet: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.small) {
            Text("Export Preview")
                .font(.headline)
            Text("This is exactly what will be written to the file.")
                .font(.callout)
                .foregroundStyle(.secondary)
            TextEditor(text: .constant(exportPreview ?? ""))
                .font(.system(.body, design: .monospaced))
                .frame(minWidth: 560, minHeight: 360)
            HStack {
                Spacer()
                Button("Cancel") { exportPreview = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Save…") {
                    if let exportPreview {
                        store.saveExport(exportPreview)
                    }
                    exportPreview = nil
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
    }
}

private extension AlertConditionState {
    var localizedAttentionName: String {
        switch self {
        case .normal:
            return String(localized: "attention.state.recovered", defaultValue: "Recovered")
        case .pending:
            return String(localized: "attention.state.pending", defaultValue: "Pending")
        case .active:
            return String(localized: "attention.state.active", defaultValue: "Active")
        }
    }
}

private extension AttentionSeverity {
    var localizedName: String {
        switch self {
        case .info:
            return String(localized: "attention.severity.info", defaultValue: "Information")
        case .warning:
            return String(localized: "attention.severity.warning", defaultValue: "Warning")
        case .critical:
            return String(localized: "attention.severity.critical", defaultValue: "Critical")
        }
    }
}
