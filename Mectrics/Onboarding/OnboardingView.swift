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
    private static let stepCount = 3
    private static let recommendedIDs: [MetricID] = [.cpu, .memory, .battery, .network]

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0:  welcomeStep
                case 1:  choicesStep
                default: optionalStep
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
            Image(systemName: MetricSymbol.name(for: id))
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
                                Label(id.localizedName, systemImage: MetricSymbol.name(for: id))
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
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .padding(ExperienceSpacing.xLarge)
    }

    /// Two switches on their own step rather than under a scrolling module list.
    /// The update question is a consent question — burying it below a fold that
    /// grows with the number of modules a Mac happens to have is how it goes
    /// unanswered.
    private var optionalStep: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.large) {
            ExperienceSectionHeader(
                title: String(
                    localized: "onboarding.optional.title",
                    defaultValue: "Two things to decide"
                ),
                subtitle: String(
                    localized: "onboarding.optional.subtitle",
                    defaultValue: "Both are off unless you turn them on, and both live in Settings afterwards."
                )
            )

            Form {
                Section {
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

                Section {
                    Toggle(isOn: $model.automaticUpdateChecks) {
                        Text("Check for updates automatically")
                        Text("Asks the update server whether a newer version exists. It sends nothing about you or your Mac, and installs nothing on its own.")
                    }
                    .accessibilityHint(
                        String(
                            localized: "onboarding.updates.hint",
                            defaultValue: "Look for new versions without being asked each time"
                        )
                    )
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            Spacer(minLength: 0)
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
                        step -= 1
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

            if step < Self.stepCount - 1 {
                Button("Continue") {
                    withAnimation(ExperienceMotion.stateChange(reduceMotion: reduceMotion)) {
                        step += 1
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
        guard let sample = model.latest[id] else { return "–" }
        switch id {
        case .cpu, .memory, .battery, .disk, .gpu:
            return MetricFormat.percent(sample.value)
        case .network:
            return "↓\(MetricFormat.menuRate(sample.detail["down"] ?? 0))"
        case .sensors:
            return "\(Int(sample.value.rounded()))°"
        case .fans:
            return "\(Int((sample.detail["maxRpm"] ?? 0).rounded())) RPM"
        }
    }
}
