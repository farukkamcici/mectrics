import AppKit
import SwiftUI

/// Borderless, non-activating panel used as the floating live widget. It never steals
/// key/main status from the frontmost app — it is display-only.
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Owns the floating panel window: creates it lazily, shows/hides it, and persists its
/// on-screen position across launches. The user resizes the width only — the height
/// follows the content (chips re-flow into rows as the width changes).
@MainActor
final class FloatingPanelController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private var panel: FloatingPanel?
    /// Content-driven height, reported by SwiftUI as chips wrap.
    private var autoHeight: CGFloat = 44

    private static let autosaveName = "mectrics.floatingPanel"

    init(model: AppModel) {
        self.model = model
    }

    /// Width is the user's; height always snaps back to the content's natural size.
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        NSSize(width: max(frameSize.width, 150), height: autoHeight)
    }

    private func applyAutoHeight(_ height: CGFloat) {
        let newHeight = max(ceil(height), 36)
        guard abs(newHeight - autoHeight) > 0.5 || abs((panel?.frame.height ?? 0) - newHeight) > 0.5
        else { return }
        autoHeight = newHeight
        guard let panel else { return }
        var frame = panel.frame
        // Keep the top edge anchored so a strip parked under the menu bar stays put.
        frame.origin.y += frame.height - newHeight
        frame.size.height = newHeight
        panel.setFrame(frame, display: true)
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
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 44),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        // Freely resizable: wide-and-thin (single strip along the screen top) up to a
        // multi-row card. The grid content re-flows to whatever fits.
        panel.contentMinSize = NSSize(width: 150, height: 36)
        panel.contentMaxSize = NSSize(width: 1600, height: 600)
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

        // The user drives the width (drag left/right edges); SwiftUI re-flows and
        // reports the resulting content height back so the window can follow it.
        let view = FloatingPanelView(model: model) { [weak self] height in
            self?.applyAutoHeight(height)
        }
        panel.contentViewController = NSHostingController(rootView: view)
        panel.delegate = self

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
