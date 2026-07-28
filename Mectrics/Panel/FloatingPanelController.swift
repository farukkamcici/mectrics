import AppKit
import SwiftUI

/// Borderless, non-activating panel used as the floating live widget. It never steals
/// key/main status from the frontmost app — it is display-only.
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Owns the floating panel window: creates it lazily, shows/hides it, and persists its
/// on-screen position across launches.
@MainActor
final class FloatingPanelController {
    private let model: AppModel
    private var panel: FloatingPanel?

    private static let autosaveName = "mectrics.floatingPanel"

    init(model: AppModel) {
        self.model = model
    }

    func setVisible(_ visible: Bool) {
        if visible {
            show()
        } else {
            panel?.orderOut(nil)
        }
    }

    private func show() {
        if panel == nil {
            panel = makePanel()
        }
        panel?.orderFrontRegardless()
    }

    private func makePanel() -> FloatingPanel {
        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.animationBehavior = .utilityWindow
        // Visible on every Space, including alongside full-screen apps.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let host = NSHostingController(rootView: FloatingPanelView(model: model))
        // Let SwiftUI drive the window size (module count changes the panel height).
        host.sizingOptions = .preferredContentSize
        panel.contentViewController = host

        // Restore the previous position; first launch goes to the top-right corner.
        let restored = panel.setFrameUsingName(Self.autosaveName)
        panel.setFrameAutosaveName(Self.autosaveName)
        if !restored, let screen = NSScreen.main {
            let visible = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: visible.maxX - panel.frame.width - 16,
                y: visible.maxY - panel.frame.height - 16
            ))
        }
        return panel
    }
}
