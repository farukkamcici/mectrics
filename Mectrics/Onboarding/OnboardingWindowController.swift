import AppKit
import SwiftUI

/// Shows the onboarding window on first launch. The app is a menu bar agent, so the
/// window is activated explicitly; closing it (by any means) marks onboarding complete
/// so it never nags again.
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private var window: NSWindow?

    init(model: AppModel) {
        self.model = model
    }

    func show() {
        let view = OnboardingView(model: model) { [weak self] in
            self?.window?.close()
        }
        let host = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: host)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.delegate = self
        window.center()
        self.window = window

        // Menu bar agent: force activation so the window actually comes to the front
        // (cooperative activation is refused when another app is frontmost at launch).
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        model.hasCompletedOnboarding = true
        window = nil
    }
}
