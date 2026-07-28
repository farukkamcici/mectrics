import SwiftUI
import MetricsKit

/// A short, optional first-run flow built around the same live readings shown in the
/// menu bar. Fine customization remains in Settings > Menu Bar.
struct OnboardingView: View {
    @Bindable var model: AppModel
    var onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = 0
    @State private var launchAtLogin = LoginItem.isEnabled

    static let contentSize = CGSize(width: 540, height: 430)
    private static let stepCount = 2
    private static let recommendedIDs: [MetricID] = [.cpu, .memory, .battery, .network]

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if step == 0 {
                    welcomeStep
                } else {
                    choicesStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            navigationBar
        }
        .frame(width: Self.contentSize.width, height: Self.contentSize.height)
    }

    private var welcomeStep: some View {
        VStack(spacing: ExperienceSpacing.xLarge) {
            VStack(spacing: ExperienceSpacing.small) {
                Image(systemName: "gauge.with.needle")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text("Your Mac, clear at a glance")
                    .font(.title.weight(.semibold))
                Text("Live essentials stay visible in the menu bar without opening a dashboard.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            livePreview

            Label(
                "Your readings stay on this Mac. Mectrics has no telemetry.",
                systemImage: "lock.shield"
            )
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, ExperienceSpacing.xLarge * 2)
        .padding(.vertical, ExperienceSpacing.xLarge)
    }

    private var livePreview: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.small) {
            HStack {
                Text("Live menu bar preview")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                let liveCount = recommendedModules.filter {
                    model.metricState(for: $0, isEnabled: true) == .live
                }.count
                Text(
                    String(
                        localized: "onboarding.liveCount",
                        defaultValue: "\(liveCount) live"
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }

            HStack(spacing: ExperienceSpacing.medium) {
                ForEach(recommendedModules, id: \.self) { id in
                    onboardingMetric(id)
                    if id != recommendedModules.last {
                        Divider().frame(height: 22)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, ExperienceSpacing.large)
            .padding(.vertical, ExperienceSpacing.medium)
            .background(
                RoundedRectangle(cornerRadius: ExperienceRadius.standard, style: .continuous)
                    .fill(.quaternary.opacity(0.55))
            )
        }
        .accessibilityElement(children: .contain)
    }

    private func onboardingMetric(_ id: MetricID) -> some View {
        let state = model.metricState(for: id, isEnabled: true)
        return HStack(spacing: ExperienceSpacing.xSmall) {
            Image(systemName: FloatingPanelView.symbol(for: id))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(previewValue(for: id))
                .monospacedDigit()
                .lineLimit(1)
            if state != .live {
                Image(systemName: state.symbolName)
                    .font(.caption2)
                    .foregroundStyle(state.tint)
                    .help(state.reason)
                    .accessibilityHidden(true)
            }
        }
        .font(.callout.weight(.semibold))
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(id.localizedName)
        .accessibilityValue(
            String(
                localized: "metric.accessibility.valueAndState",
                defaultValue: "\(previewValue(for: id)), \(state.localizedName)"
            )
        )
    }

    private var choicesStep: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.large) {
            ExperienceSectionHeader(
                title: String(
                    localized: "onboarding.modules.title",
                    defaultValue: "Start with the essentials"
                ),
                subtitle: String(
                    localized: "onboarding.modules.subtitle",
                    defaultValue: "Recommended modules are marked. Fine-tune components later in Settings."
                )
            )

            Form {
                Section("Menu bar modules") {
                    ForEach(recommendedModules, id: \.self) { id in
                        Toggle(isOn: Binding(
                            get: { model.enabledModules.contains(id) },
                            set: { model.setEnabled($0, for: id) }
                        )) {
                            HStack {
                                Label(id.localizedName, systemImage: FloatingPanelView.symbol(for: id))
                                Spacer()
                                Text("Recommended")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityLabel(id.localizedName)
                        .accessibilityHint(
                            String(
                                localized: "onboarding.recommended.hint",
                                defaultValue: "Recommended menu bar module"
                            )
                        )
                    }

                    if additionalModules.isEmpty == false {
                        ForEach(additionalModules, id: \.self) { id in
                            Toggle(
                                id.localizedName,
                                isOn: Binding(
                                    get: { model.enabledModules.contains(id) },
                                    set: { model.setEnabled($0, for: id) }
                                )
                            )
                        }
                    }
                }

                Section("Optional") {
                    Toggle(isOn: $launchAtLogin) {
                        Text("Launch at login")
                        Text("Start Mectrics automatically after you sign in.")
                    }
                    .accessibilityLabel(
                        String(localized: "settings.launchAtLogin", defaultValue: "Launch at login")
                    )
                    .accessibilityHint(
                        String(
                            localized: "settings.launchAtLogin.hint",
                            defaultValue: "Start Mectrics automatically after you sign in"
                        )
                    )
                    .onChange(of: launchAtLogin) { _, enabled in
                        LoginItem.setEnabled(enabled)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .padding(ExperienceSpacing.xLarge)
    }

    private var navigationBar: some View {
        HStack {
            if step == 0 {
                Button("Skip Setup", action: onFinish)
            } else {
                Button("Back") {
                    withAnimation(ExperienceMotion.stateChange(reduceMotion: reduceMotion)) {
                        step = 0
                    }
                }
            }

            Spacer()
            Text(
                String(
                    localized: "onboarding.progress",
                    defaultValue: "Step \(step + 1) of \(Self.stepCount)"
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .accessibilityLabel(
                String(
                    localized: "onboarding.progress.accessibility",
                    defaultValue: "Step \(step + 1) of \(Self.stepCount)"
                )
            )
            Spacer()

            if step == 0 {
                Button("Continue") {
                    withAnimation(ExperienceMotion.stateChange(reduceMotion: reduceMotion)) {
                        step = 1
                    }
                }
                .keyboardShortcut(.defaultAction)
            } else {
                Button("Start Monitoring", action: onFinish)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, ExperienceSpacing.large)
        .padding(.vertical, ExperienceSpacing.medium)
    }

    private var recommendedModules: [MetricID] {
        Self.recommendedIDs.filter(model.availableModules.contains)
    }

    private var additionalModules: [MetricID] {
        model.availableModules.filter { !Self.recommendedIDs.contains($0) }
    }

    private func previewValue(for id: MetricID) -> String {
        guard let sample = model.latest[id] else { return "—" }
        switch id {
        case .cpu, .memory, .battery, .disk, .gpu, .bluetooth:
            return MetricFormat.percent(sample.value)
        case .network:
            return "↓\(MetricFormat.menuRate(sample.detail["down"] ?? 0))"
        case .sensors:
            return "\(Int(sample.value.rounded()))°"
        case .fans:
            return "\(Int((sample.detail["maxRpm"] ?? 0).rounded())) RPM"
        case .clock:
            return "—"
        }
    }
}
