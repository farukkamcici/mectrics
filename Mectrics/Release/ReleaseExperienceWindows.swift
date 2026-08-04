import AppKit
import SwiftUI

enum WhatsNewPolicy {
    static func shouldPresent(
        currentVersion: String,
        storedVersion: String?,
        hasNotes: Bool = true
    ) -> Bool {
        guard let storedVersion else { return false }
        guard hasNotes else { return false }
        return storedVersion != currentVersion
    }
}

/// One line of release notes.
struct ReleaseHighlight: Identifiable {
    let id: String
    let symbol: String
    let title: String
    let description: String
}

/// What each release is worth telling a person about, keyed by the version it shipped in.
///
/// This used to be a single hardcoded list, so every upgrade showed the same three items
/// no matter how long ago they shipped — an upgrade to 1.5.0 was greeted with news from
/// 1.2. Notes now belong to a version, and a version with nothing written for it shows no
/// window rather than stale news.
///
/// A patch release never stands alone. It carries the notes of the minor release it fixes
/// and appends its own, so 1.6.1 reads as "what 1.6 brought, plus what changed since"
/// rather than presenting a fix as if it were the whole release. Someone who skipped
/// 1.6.0 still learns what it added.
enum ReleaseHighlights {
    static func notes(for version: String) -> [ReleaseHighlight] {
        switch version {
        case "1.6.1": return oneSixZero + oneSixOne
        case "1.6.0": return oneSixZero
        case "1.5.0": return oneFiveZero
        default:      return []
        }
    }

    static var current: [ReleaseHighlight] {
        notes(for: Bundle.main.marketingVersion)
    }

    private static var oneSixOne: [ReleaseHighlight] {
        [
            ReleaseHighlight(
                id: "onboarding",
                symbol: "list.number",
                title: String(
                    localized: "whatsNew.1_6_1.onboarding.title",
                    defaultValue: "A clearer first run"
                ),
                description: String(
                    localized: "whatsNew.1_6_1.onboarding.description",
                    defaultValue: "Launch at login and the update question now have a step of their own. They used to sit under the module list, where they fell below the fold on Macs with more hardware to report."
                )
            )
        ]
    }

    private static var oneSixZero: [ReleaseHighlight] {
        [
            ReleaseHighlight(
                id: "updates",
                symbol: "arrow.down.circle",
                title: String(
                    localized: "whatsNew.1_6_0.updates.title",
                    defaultValue: "Updates can find you now"
                ),
                description: String(
                    localized: "whatsNew.1_6_0.updates.description",
                    defaultValue: "Mectrics can check whether a newer version exists instead of waiting for you to look. It asks first, the request says nothing about you or your Mac, and nothing installs on its own. Change it any time in Settings."
                )
            )
        ]
    }

    private static var oneFiveZero: [ReleaseHighlight] {
        [
            ReleaseHighlight(
                id: "settings",
                symbol: "gauge.with.dots.needle.33percent",
                title: String(
                    localized: "whatsNew.1_5_0.settings.title",
                    defaultValue: "Settings stays light while it is open"
                ),
                description: String(
                    localized: "whatsNew.1_5_0.settings.description",
                    defaultValue: "Leaving the Settings window open used to make Mectrics work harder the longer it stayed there. It now costs little more than the menu bar on its own."
                )
            ),
            ReleaseHighlight(
                id: "watch",
                symbol: "eye.trianglebadge.exclamationmark",
                title: String(
                    localized: "whatsNew.1_5_0.watch.title",
                    defaultValue: "Alerts admit what they cannot see"
                ),
                description: String(
                    localized: "whatsNew.1_5_0.watch.description",
                    defaultValue: "A reading that failed is no longer reported as healthy. Coverage and freshness are part of every status record."
                )
            ),
            ReleaseHighlight(
                id: "doctor",
                symbol: "stethoscope",
                title: String(
                    localized: "whatsNew.1_5_0.doctor.title",
                    defaultValue: "A doctor for headless Macs"
                ),
                description: String(
                    localized: "whatsNew.1_5_0.doctor.description",
                    defaultValue: "mectrics doctor explains a silent watch — permissions, configuration, and the update channel — as text or JSON."
                )
            )
        ]
    }
}

extension Bundle {
    var marketingVersion: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }
}

@MainActor
final class AboutWindowController: NSObject, NSWindowDelegate {
    private let dock: DockPresence
    private var window: NSWindow?

    init(dock: DockPresence) {
        self.dock = dock
        super.init()
    }

    func show() {
        dock.windowDidOpen(self)
        if window == nil {
            window = makeWindow()
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.clearInitialFocus()
    }

    func windowWillClose(_ notification: Notification) {
        dock.windowWillClose(self)
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
    private let dock: DockPresence
    private var window: NSWindow?

    init(dock: DockPresence) {
        self.dock = dock
        super.init()
    }

    func show() {
        dock.windowDidOpen(self)
        if window == nil {
            window = makeWindow()
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.clearInitialFocus()
    }

    func windowWillClose(_ notification: Notification) {
        dock.windowWillClose(self)
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
        ) as? String ?? "–"
        let build = bundle.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "–"
        return String(
            localized: "about.versionBuild",
            defaultValue: "Version \(version) (\(build))"
        )
    }
}

private struct WhatsNewView: View {
    let close: () -> Void
    private let notes = ReleaseHighlights.current

    init(close: @escaping () -> Void) {
        self.close = close
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.large) {
            VStack(alignment: .leading, spacing: ExperienceSpacing.xSmall) {
                Text(verbatim: "Mectrics \(Bundle.main.marketingVersion)")
                    .font(.largeTitle.weight(.semibold))
                Text("What changed in this update")
                    .foregroundStyle(.secondary)
            }
            if notes.isEmpty {
                Text("This update has no release notes.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(notes) { note in
                    feature(note)
                }
            }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("Continue", action: close)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(ExperienceSpacing.xLarge)
    }

    private func feature(_ note: ReleaseHighlight) -> some View {
        HStack(alignment: .top, spacing: ExperienceSpacing.medium) {
            Image(systemName: note.symbol)
                .font(.title2)
                .frame(width: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: ExperienceSpacing.xSmall) {
                Text(note.title)
                    .font(.headline)
                Text(note.description)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
