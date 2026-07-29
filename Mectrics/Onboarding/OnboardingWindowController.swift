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
            positionAtVisibleScreenCenter(window)
            window.makeKeyAndOrderFront(nil)
        window.clearInitialFocus()
            window.clearInitialFocus()
            return
        }

        model.beginOnboardingPreview()
        let view = OnboardingView(model: model) { [weak self] in
            self?.window?.close()
        }
        let host = NSHostingController(rootView: view.quietFocusRing())
        let window = OnboardingWindow(contentViewController: host)
        window.styleMask = [.titled, .closable]
        window.title = String(
            localized: "onboarding.window.title",
            defaultValue: "Welcome to Mectrics"
        )
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(
            width: OnboardingView.contentSize.width,
            height: OnboardingView.contentSize.height
        ))
        window.standardWindowButton(.miniaturizeButton)?.isEnabled = false
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        window.isMovableByWindowBackground = true
        window.delegate = self
        self.window = window

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        positionAtVisibleScreenCenter(window)
        window.makeKeyAndOrderFront(nil)
        window.clearInitialFocus()
    }

    private func positionAtVisibleScreenCenter(_ window: NSWindow) {
        guard let screen = NSScreen.main ?? window.screen ?? NSScreen.screens.first else {
            window.center()
            return
        }
        let visibleFrame = screen.visibleFrame
        let frame = window.frame
        window.setFrameOrigin(NSPoint(
            x: visibleFrame.midX - frame.width / 2,
            y: visibleFrame.midY - frame.height / 2
        ))
    }

    func windowWillClose(_ notification: Notification) {
        model.hasCompletedOnboarding = true
        model.endOnboardingPreview()
        window = nil
        onFinished()
    }
}
