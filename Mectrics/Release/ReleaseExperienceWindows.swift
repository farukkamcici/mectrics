import AppKit
import SwiftUI

enum WhatsNewPolicy {
    static func shouldPresent(
        currentVersion: String,
        storedVersion: String?
    ) -> Bool {
        guard let storedVersion else { return false }
        return storedVersion != currentVersion
    }
}

@MainActor
final class AboutWindowController: NSObject, NSWindowDelegate {
    private let onClose: () -> Void
    private var window: NSWindow?

    init(onClose: @escaping () -> Void = {}) {
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
        let host = NSHostingController(
            rootView: AboutMectricsView().quietFocusRing()
        )
        host.sizingOptions = []
        let window = NSWindow(contentViewController: host)
        window.title = String(
            localized: "about.title",
            defaultValue: "About Mectrics"
        )
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 440, height: 440))
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }
}

@MainActor
final class WhatsNewWindowController: NSObject, NSWindowDelegate {
    private let onClose: () -> Void
    private var window: NSWindow?

    init(onClose: @escaping () -> Void = {}) {
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
        let host = NSHostingController(
            rootView: WhatsNewView {
                self.window?.performClose(nil)
            }
            .quietFocusRing()
        )
        host.sizingOptions = []
        let window = NSWindow(contentViewController: host)
        window.title = String(
            localized: "whatsNew.title",
            defaultValue: "What’s New in Mectrics"
        )
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 520, height: 430))
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }
}

private struct AboutMectricsView: View {
    var body: some View {
        VStack(spacing: ExperienceSpacing.medium) {
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 96, height: 96)
                    .accessibilityHidden(true)
            }
            Text("Mectrics")
                .font(.title.weight(.semibold))
            Text(Self.version)
                .foregroundStyle(.secondary)
            Text("A lightweight, private system monitor for Mac.")
                .multilineTextAlignment(.center)
            Label(
                "All readings stay on this Mac. Mectrics has no telemetry.",
                systemImage: "lock.shield"
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            VStack(spacing: ExperienceSpacing.small) {
                Link(
                    "Website and Source",
                    destination: URL(
                        string: "https://github.com/farukkamcici/mectrics"
                    )!
                )
                Link(
                    "MIT License",
                    destination: URL(
                        string: "https://github.com/farukkamcici/mectrics/blob/main/LICENSE"
                    )!
                )
            }
            Divider()
            LabeledContent(
                "Updates",
                value: UpdateController.localizedStatus
            )
            .font(.callout)
        }
        .padding(ExperienceSpacing.xLarge)
    }

    private static var version: String {
        let bundle = Bundle.main
        let version = bundle.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "—"
        let build = bundle.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "—"
        return String(
            localized: "about.versionBuild",
            defaultValue: "Version \(version) (\(build))"
        )
    }
}

private struct WhatsNewView: View {
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.large) {
            Text("A calmer view of Mac health")
                .font(.largeTitle.weight(.semibold))
            feature(
                "Widgets that open the right metric",
                symbol: "rectangle.3.group",
                description: "Small, medium, and large widgets share live local readings with Mectrics."
            )
            feature(
                "Explainable alerts and Attention Log",
                symbol: "exclamationmark.bubble",
                description: "Rules show their live state and meaningful incidents remain available locally."
            )
            feature(
                "Automatic Energy Guard",
                symbol: "leaf",
                description: "Mectrics reduces expensive monitoring when power or thermal headroom is limited."
            )
            HStack {
                Spacer()
                Button("Continue", action: close)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(ExperienceSpacing.xLarge)
    }

    private func feature(
        _ title: LocalizedStringKey,
        symbol: String,
        description: LocalizedStringKey
    ) -> some View {
        HStack(alignment: .top, spacing: ExperienceSpacing.medium) {
            Image(systemName: symbol)
                .font(.title2)
                .frame(width: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: ExperienceSpacing.xSmall) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
