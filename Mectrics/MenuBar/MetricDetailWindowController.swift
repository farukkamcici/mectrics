import AppKit
import MetricsKit
import SwiftUI

private final class MetricDetailWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        performClose(sender)
    }
}

/// Presents metric detail content for entry points that do not have a status-item
/// anchor, such as widgets and external URLs. One controller owns one reusable window.
@MainActor
final class MetricDetailWindowController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private let dock: DockPresence
    private let onVisibilityChanged: (MetricID, Bool) -> Void
    private var window: NSWindow?
    private var currentMetricID: MetricID?

    private static let initialContentSize = NSSize(width: 340, height: 500)
    private static let minimumContentSize = NSSize(width: 320, height: 360)
    private static let frameAutosaveName = "mectrics.metricDetail"

    init(
        model: AppModel,
        dock: DockPresence,
        onVisibilityChanged: @escaping (MetricID, Bool) -> Void = { _, _ in }
    ) {
        self.model = model
        self.dock = dock
        self.onVisibilityChanged = onVisibilityChanged
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func show(metricID: MetricID) {
        dock.windowDidOpen(self)
        if window == nil {
            window = makeWindow()
        }
        if currentMetricID != metricID {
            if window?.isVisible == true, let currentMetricID {
                onVisibilityChanged(currentMetricID, false)
            }
            currentMetricID = metricID
            updateContent(for: metricID)
        }
        window?.title = metricID.localizedName
        clampToVisibleScreen()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.clearInitialFocus()
        onVisibilityChanged(metricID, true)
    }

    func windowWillClose(_ notification: Notification) {
        dock.windowWillClose(self)
        if let currentMetricID {
            onVisibilityChanged(currentMetricID, false)
        }
    }

    private func makeWindow() -> NSWindow {
        let window = MetricDetailWindow(
            contentRect: NSRect(origin: .zero, size: Self.initialContentSize),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentMinSize = Self.minimumContentSize
        window.delegate = self
        window.titlebarSeparatorStyle = .automatic
        window.standardWindowButton(.miniaturizeButton)?.isEnabled = false
        window.setFrameAutosaveName(Self.frameAutosaveName)
        if !window.setFrameUsingName(Self.frameAutosaveName) {
            window.center()
        }
        return window
    }

    private func updateContent(for metricID: MetricID) {
        let content = ScrollView {
            DetailPopoverView(
                model: model,
                moduleID: metricID,
                showsGlobalActions: false,
                honorsEnabledState: true
            )
                .frame(maxWidth: .infinity)
        }
        let host = NSHostingController(rootView: content.quietFocusRing())
        host.sizingOptions = []
        window?.contentViewController = host
    }

    @objc private func screenParametersDidChange() {
        clampToVisibleScreen()
    }

    private func clampToVisibleScreen() {
        guard let window else { return }
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }

        let target = screens.max { lhs, rhs in
            Self.area(of: lhs.visibleFrame.intersection(window.frame))
                < Self.area(of: rhs.visibleFrame.intersection(window.frame))
        } ?? NSScreen.main ?? screens[0]
        let visible = target.visibleFrame
        var frame = window.frame
        frame.size.width = min(max(frame.width, Self.minimumContentSize.width), visible.width)
        frame.size.height = min(max(frame.height, Self.minimumContentSize.height), visible.height)
        frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        window.setFrame(frame, display: window.isVisible)
    }

    private static func area(of rect: NSRect) -> CGFloat {
        rect.isNull ? 0 : rect.width * rect.height
    }
}
