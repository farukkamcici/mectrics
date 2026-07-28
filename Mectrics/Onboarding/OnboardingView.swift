import SwiftUI
import MetricsKit

/// Three-step first-launch onboarding: welcome → module selection → setup.
/// Shown once (see `AppModel.hasCompletedOnboarding`); every choice here can be
/// changed later in Settings.
struct OnboardingView: View {
    @Bindable var model: AppModel
    var onFinish: () -> Void

    @State private var step = 0
    @State private var launchAtLogin = LoginItem.isEnabled

    private static let stepCount = 3

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0:  welcomeStep
                case 1:  modulesStep
                default: setupStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            navigationBar
        }
        .frame(width: 460, height: 440)
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: 14) {
            Image(systemName: "gauge.with.needle")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.tint)
            Text("Welcome to Mectrics")
                .font(.title.weight(.semibold))
            Text("A lightweight system monitor that lives in your menu bar — CPU, memory, battery, network and disk at a glance.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Label("Zero telemetry — no data ever leaves your device",
                  systemImage: "lock.shield")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
        }
        .padding(.horizontal, 40)
    }

    private var modulesStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            stepHeader(
                title: String(localized: "onboarding.modules.title", defaultValue: "Choose your modules"),
                subtitle: String(localized: "onboarding.modules.subtitle",
                                 defaultValue: "Each module appears as its own item in the menu bar. You can change this anytime in Settings.")
            )
            Form {
                ForEach(model.availableModules, id: \.self) { id in
                    Toggle(id.localizedName, isOn: Binding(
                        get: { model.enabledModules.contains(id) },
                        set: { model.setEnabled($0, for: id) }
                    ))
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .padding(.top, 24)
        .padding(.horizontal, 24)
    }

    private var setupStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            stepHeader(
                title: String(localized: "onboarding.setup.title", defaultValue: "Make it yours"),
                subtitle: String(localized: "onboarding.setup.subtitle",
                                 defaultValue: "Two optional touches — both can be changed later in Settings.")
            )
            Form {
                Toggle(isOn: $launchAtLogin) {
                    Text("Launch at login")
                    Text("Start Mectrics automatically when you log in.")
                }
                .onChange(of: launchAtLogin) { _, newValue in
                    LoginItem.setEnabled(newValue)
                }
                Toggle(isOn: $model.showFloatingPanel) {
                    Text("Show floating panel")
                    Text("A small always-on-top widget with live metrics.")
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .padding(.top, 24)
        .padding(.horizontal, 24)
    }

    private func stepHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.title2.weight(.semibold))
            Text(subtitle).font(.callout).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Navigation

    private var navigationBar: some View {
        HStack {
            if step > 0 {
                Button("Back") { withAnimation { step -= 1 } }
            }
            Spacer()
            HStack(spacing: 6) {
                ForEach(0..<Self.stepCount, id: \.self) { i in
                    Circle()
                        .fill(i == step ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 7, height: 7)
                }
            }
            Spacer()
            if step < Self.stepCount - 1 {
                Button("Continue") { withAnimation { step += 1 } }
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Get Started") { onFinish() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
    }
}
