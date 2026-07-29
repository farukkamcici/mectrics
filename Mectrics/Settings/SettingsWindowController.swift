import AppKit
import SwiftUI

/// Settings closes with Escape like a native preferences window.
private final class SettingsWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        performClose(sender)
    }
}

/// Owns the settings window. Managed manually because this menu bar app has no SwiftUI
/// scenes. The window behaves like a regular Mac preferences window: it has a useful
/// centered initial size, restores its pane and frame, and remains resizable.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    enum Pane: Int {
        case general
        case menuBar
        case alerts
    }

    private let model: AppModel
    private let onClose: () -> Void
    private var window: NSWindow?
    private weak var tabController: SettingsTabViewController?
    private let defaults = UserDefaults.standard

    // One size for every pane: switching tabs should move the selection, not the
    // window. The user's own resize is still restored from the frame autosave.
    private static let initialContentSize = NSSize(width: 620, height: 540)
    private static let minimumContentSize = NSSize(width: 560, height: 460)
    private static let frameAutosaveName = "mectrics.settings"
    private static let selectedPaneKey = "settings.selectedPane"
    private static let toolbarIdentifier = NSToolbar.Identifier("mectrics.settings.toolbar")
    private static let generalIdentifier = NSToolbarItem.Identifier("mectrics.settings.general")
    private static let menuBarIdentifier = NSToolbarItem.Identifier("mectrics.settings.menuBar")
    private static let alertsIdentifier = NSToolbarItem.Identifier("mectrics.settings.alerts")

    init(model: AppModel, onClose: @escaping () -> Void = {}) {
        self.model = model
        self.onClose = onClose
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(toolbarItemWasRemoved(_:)),
            name: NSToolbar.didRemoveItemNotification,
            object: nil
        )
    }

    func show(pane: Pane? = nil) {
        NSApp.setActivationPolicy(.regular)
        if window == nil {
            window = makeWindow()
        }
        if let pane, let tabs = tabController {
            tabs.selectedTabViewItemIndex = pane.rawValue
            window?.toolbar?.selectedItemIdentifier = Self.toolbarIdentifiers[pane.rawValue]
        }
        clampToVisibleScreen()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.clearInitialFocus()
        if let tabs = window?.contentViewController as? NSTabViewController,
           tabs.tabViewItems.indices.contains(tabs.selectedTabViewItemIndex) {
            window?.title = tabs.tabViewItems[tabs.selectedTabViewItemIndex].label
        }
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }

    private func makeWindow() -> NSWindow {
        let tabs = SettingsTabViewController()
        tabs.tabStyle = .unspecified
        tabs.loadView()
        tabs.tabView.tabViewType = .noTabsNoBorder
        tabs.addTabViewItem(makeTab(
            GeneralSettingsTab(model: model),
            label: String(localized: "settings.tab.general", defaultValue: "General"),
            symbol: "gearshape"
        ))
        tabs.addTabViewItem(makeTab(
            MenuBarBuilderView(model: model),
            label: String(localized: "settings.tab.menuBar", defaultValue: "Menu Bar"),
            symbol: "square.grid.2x2"
        ))
        tabs.addTabViewItem(makeTab(
            AlertsSettingsTab(model: model),
            label: String(localized: "settings.tab.alerts", defaultValue: "Alerts"),
            symbol: "bell.badge"
        ))
        // The window toolbar is the only pane switcher; keep the content tab view
        // borderless and hidden from layout.
        tabs.tabView.tabViewType = .noTabsNoBorder

        let selectedPane = min(
            max(defaults.integer(forKey: Self.selectedPaneKey), 0),
            tabs.tabViewItems.count - 1
        )
        tabs.selectedTabViewItemIndex = selectedPane
        tabController = tabs

        let window = SettingsWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable, .resizable]
        window.title = tabs.tabViewItems[selectedPane].label
        window.isReleasedWhenClosed = false
        window.contentMinSize = Self.minimumContentSize
        window.setContentSize(Self.initialContentSize)
        window.delegate = self
        window.titleVisibility = .visible
        window.titlebarSeparatorStyle = .automatic
        window.standardWindowButton(.miniaturizeButton)?.isEnabled = false
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        let toolbar = NSToolbar(identifier: Self.toolbarIdentifier)
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.selectedItemIdentifier = Self.toolbarIdentifiers[selectedPane]
        window.toolbar = toolbar

        let restored = window.setFrameUsingName(Self.frameAutosaveName)
        window.setFrameAutosaveName(Self.frameAutosaveName)
        if !restored {
            window.center()
        }

        tabs.onSelectionChanged = { [weak window] index in
            guard let window,
                  tabs.tabViewItems.indices.contains(index) else { return }
            UserDefaults.standard.set(index, forKey: Self.selectedPaneKey)
            let title = tabs.tabViewItems[index].label
            window.title = title
            DispatchQueue.main.async { [weak window] in
                window?.title = title
            }
        }
        return window
    }

    @objc private func selectPane(_ sender: NSToolbarItem) {
        guard let index = Self.toolbarIdentifiers.firstIndex(of: sender.itemIdentifier),
              let tabs = tabController else { return }
        tabs.selectedTabViewItemIndex = index
        window?.toolbar?.selectedItemIdentifier = sender.itemIdentifier
    }

    private func makeTab(_ view: some View, label: String,
                         symbol: String) -> NSTabViewItem {
        let host = NSHostingController(rootView: view.quietFocusRing())
        // The window owns sizing. SwiftUI fills the available content area without
        // trying to resize the AppKit window as live metric values change.
        host.sizingOptions = []
        host.title = label
        let item = NSTabViewItem(viewController: host)
        item.label = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        return item
    }

    @objc private func screenParametersDidChange() {
        clampToVisibleScreen()
    }

    /// AppKit exposes a Remove accessibility action even for a noncustomizable
    /// toolbar. Restore any pane item immediately so keyboard and assistive
    /// technology cannot accidentally make Settings navigation incomplete.
    @objc private func toolbarItemWasRemoved(_ notification: Notification) {
        guard let toolbar = notification.object as? NSToolbar,
              toolbar.identifier == Self.toolbarIdentifier else { return }
        DispatchQueue.main.async {
            let current = Set(toolbar.items.map(\.itemIdentifier))
            for (index, identifier) in Self.toolbarIdentifiers.enumerated()
                where !current.contains(identifier) {
                toolbar.insertItem(
                    withItemIdentifier: identifier,
                    at: min(index, toolbar.items.count)
                )
            }
        }
    }

    /// Keeps a restored window fully reachable after a display is removed or changed.
    private func clampToVisibleScreen() {
        guard let window else { return }
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }

        let target = screens.max { lhs, rhs in
            lhs.visibleFrame.intersection(window.frame).area
                < rhs.visibleFrame.intersection(window.frame).area
        } ?? NSScreen.main ?? screens[0]
        let visible = target.visibleFrame
        var frame = window.frame
        frame.size.width = min(max(frame.width, Self.minimumContentSize.width), visible.width)
        frame.size.height = min(max(frame.height, Self.minimumContentSize.height), visible.height)
        frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        window.setFrame(frame, display: window.isVisible)
    }
}

extension SettingsWindowController: NSToolbarDelegate {
    private static var toolbarIdentifiers: [NSToolbarItem.Identifier] {
        [generalIdentifier, menuBarIdentifier, alertsIdentifier]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Self.toolbarIdentifiers
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Self.toolbarIdentifiers
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Self.toolbarIdentifiers
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard let index = Self.toolbarIdentifiers.firstIndex(of: itemIdentifier) else {
            return nil
        }
        let labels = [
            String(localized: "settings.tab.general", defaultValue: "General"),
            String(localized: "settings.tab.menuBar", defaultValue: "Menu Bar"),
            String(localized: "settings.tab.alerts", defaultValue: "Alerts")
        ]
        let symbols = ["gearshape", "square.grid.2x2", "bell.badge"]
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = labels[index]
        item.paletteLabel = labels[index]
        item.image = NSImage(
            systemSymbolName: symbols[index],
            accessibilityDescription: labels[index]
        )
        item.target = self
        item.action = #selector(selectPane(_:))
        return item
    }
}

private extension NSRect {
    var area: CGFloat {
        isNull ? 0 : width * height
    }
}

/// Keeps the window title and persisted selection in sync with the selected tab.
private final class SettingsTabViewController: NSTabViewController {
    var onSelectionChanged: ((Int) -> Void)?

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        onSelectionChanged?(selectedTabViewItemIndex)
    }
}
