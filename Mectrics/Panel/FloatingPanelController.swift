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
struct FloatingPanelGeometry {
    static let snapThreshold: CGFloat = 12

    static func adjustedFrame(
        _ frame: NSRect,
        visibleFrame: NSRect,
        snap: Bool
    ) -> NSRect {
        var adjusted = frame
        adjusted.size.width = min(adjusted.width, visibleFrame.width)
        adjusted.size.height = min(adjusted.height, visibleFrame.height)
        adjusted.origin.x = min(
            max(adjusted.minX, visibleFrame.minX),
            visibleFrame.maxX - adjusted.width
        )
        adjusted.origin.y = min(
            max(adjusted.minY, visibleFrame.minY),
            visibleFrame.maxY - adjusted.height
        )
        guard snap else { return adjusted }

        if abs(adjusted.minX - visibleFrame.minX) <= snapThreshold {
            adjusted.origin.x = visibleFrame.minX
        } else if abs(adjusted.maxX - visibleFrame.maxX) <= snapThreshold {
            adjusted.origin.x = visibleFrame.maxX - adjusted.width
        }
        if abs(adjusted.minY - visibleFrame.minY) <= snapThreshold {
            adjusted.origin.y = visibleFrame.minY
        } else if abs(adjusted.maxY - visibleFrame.maxY) <= snapThreshold {
            adjusted.origin.y = visibleFrame.maxY - adjusted.height
        }
        return adjusted
    }
}

@MainActor
final class FloatingPanelController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private var panel: FloatingPanel?
    private var isAdjustingFrame = false
    private let defaults = UserDefaults.standard

    private static let autosaveName = "mectrics.floatingPanel"
    private static let placementsKey = "floatingPanel.placementsByDisplay"

    init(model: AppModel) {
        self.model = model
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
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
            self.setAdjustedFrame(frame, snap: false)
        }
    }

    func windowDidMove(_ notification: Notification) {
        guard !isAdjustingFrame else { return }
        setAdjustedFrame(panel?.frame, snap: true)
        savePlacement()
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
        panel.animationBehavior = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? .none
            : .utilityWindow
        // Visible on every Space, including alongside full-screen apps.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self

        // Sizing is manual (refreshSize) — automatic hosting sizing recurses on
        // borderless panels; see refreshSize.
        panel.contentViewController = NSHostingController(rootView: FloatingPanelView(model: model))

        // Restore the previous position; first launch goes to the top-right corner.
        let restored = restorePlacement(for: panel)
            || panel.setFrameUsingName(Self.autosaveName)
        panel.setFrameAutosaveName(Self.autosaveName)
        if !restored, let screen = NSScreen.main {
            let visible = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: visible.maxX - panel.frame.width - 16,
                y: visible.maxY - panel.frame.height - 16
            ))
        }
        self.panel = panel
        setAdjustedFrame(panel.frame, snap: false)
        return panel
    }

    @objc private func screenParametersDidChange() {
        setAdjustedFrame(panel?.frame, snap: false)
        savePlacement()
    }

    private func setAdjustedFrame(_ proposed: NSRect?, snap: Bool) {
        guard let panel, let proposed, let screen = bestScreen(for: proposed) else {
            return
        }
        let adjusted = FloatingPanelGeometry.adjustedFrame(
            proposed,
            visibleFrame: screen.visibleFrame,
            snap: snap
        )
        guard adjusted != panel.frame else { return }
        isAdjustingFrame = true
        panel.setFrame(adjusted, display: panel.isVisible)
        isAdjustingFrame = false
    }

    private func bestScreen(for frame: NSRect) -> NSScreen? {
        NSScreen.screens.max { lhs, rhs in
            lhs.visibleFrame.intersection(frame).area
                < rhs.visibleFrame.intersection(frame).area
        } ?? NSScreen.main
    }

    private func savePlacement() {
        guard let panel, let screen = bestScreen(for: panel.frame),
              let displayID = Self.displayID(for: screen) else { return }
        var placements = defaults.dictionary(
            forKey: Self.placementsKey
        ) as? [String: String] ?? [:]
        placements[displayID] = NSStringFromRect(panel.frame)
        defaults.set(placements, forKey: Self.placementsKey)
    }

    private func restorePlacement(for panel: NSPanel) -> Bool {
        guard let screen = NSScreen.main,
              let displayID = Self.displayID(for: screen),
              let placements = defaults.dictionary(
                forKey: Self.placementsKey
              ) as? [String: String],
              let rawFrame = placements[displayID] else {
            return false
        }
        let restored = NSRectFromString(rawFrame)
        guard restored.width > 0, restored.height > 0 else { return false }
        panel.setFrame(
            FloatingPanelGeometry.adjustedFrame(
                restored,
                visibleFrame: screen.visibleFrame,
                snap: false
            ),
            display: false
        )
        return true
    }

    private static func displayID(for screen: NSScreen) -> String? {
        guard let number = screen.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")
        ] as? NSNumber else {
            return nil
        }
        return number.stringValue
    }
}

private extension NSRect {
    var area: CGFloat {
        isNull ? 0 : width * height
    }
}
