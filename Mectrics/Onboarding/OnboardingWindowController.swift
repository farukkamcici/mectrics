import AppKit
import SwiftUI

private final class OnboardingWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        performClose(sender)
    }
}

/// Shows the onboarding window on first launch. Closing it (by any means) marks
/// onboarding complete. It can be opened again later from Help.
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private let onFinished: () -> Void
    private var window: NSWindow?

    init(model: AppModel, onFinished: @escaping () -> Void = {}) {
        self.model = model
        self.onFinished = onFinished
    }

    func show() {
        if let window {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        model.beginOnboardingPreview()
        let view = OnboardingView(model: model) { [weak self] in
            self?.window?.close()
        }
        let host = NSHostingController(rootView: view)
        let window = OnboardingWindow(contentViewController: host)
        window.styleMask = [.titled, .closable]
        window.title = String(
            localized: "onboarding.window.title",
            defaultValue: "Welcome to Mectrics"
        )
        window.isReleasedWhenClosed = false
        window.standardWindowButton(.miniaturizeButton)?.isEnabled = false
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        window.isMovableByWindowBackground = true
        window.delegate = self
        window.center()
        self.window = window

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        model.hasCompletedOnboarding = true
        model.endOnboardingPreview()
        window = nil
        onFinished()
    }
}
