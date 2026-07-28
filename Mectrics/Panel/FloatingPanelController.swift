import AppKit
import SwiftUI

/// Borderless, non-activating panel used as the floating live widget. It never steals
/// key/main status from the frontmost app — it is display-only.
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Owns the floating panel window: creates it lazily, shows/hides it, and persists its
/// on-screen position across launches. The panel sizes itself to its content — the
/// layout (strip/card) is a Settings toggle, not a manual resize.
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

    /// Re-measures the SwiftUI content and fits the window to it, keeping the top
    /// edge anchored. Called when the layout toggle or the module set changes —
    /// NOT via NSHostingController's automatic sizing, which recursed into a
    /// windowDidLayout ↔ setFrame loop on this borderless panel and blew the stack.
    func refreshSize() {
        guard let panel, let view = panel.contentViewController?.view else { return }
        DispatchQueue.main.async {
            view.layoutSubtreeIfNeeded()
            let size = view.fittingSize
            guard size.width > 1, size.height > 1 else { return }
            var frame = panel.frame
            guard abs(frame.width - size.width) > 0.5 || abs(frame.height - size.height) > 0.5
            else { return }
            frame.origin.y += frame.height - size.height
            frame.size = size
            panel.setFrame(frame, display: true)
        }
    }

    private func show() {
        if panel == nil {
            panel = makePanel()
        }
        panel?.orderFrontRegardless()
        refreshSize()
    }

    private func makePanel() -> FloatingPanel {
        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 44),
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

        // Sizing is manual (refreshSize) — automatic hosting sizing recurses on
        // borderless panels; see refreshSize.
        panel.contentViewController = NSHostingController(rootView: FloatingPanelView(model: model))

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
