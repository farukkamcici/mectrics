import AppKit
import SwiftUI
import MetricsKit

/// Creates and updates the menu bar items and manages the detail popover on click.
@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {
    var onDetailVisibilityChanged: ((MetricID, Bool) -> Void)?

    private let model: AppModel
    /// One status item per enabled (module, component) pair, keyed "module|component".
    private var items: [String: MetricStatusItem] = [:]
    private var compactHealthItem: CompactHealthStatusItem?
    private let popover = NSPopover()
    private var popoverModuleID: MetricID?
    private var popoverIsHealth = false

    init(model: AppModel) {
        self.model = model
        super.init()
        // Native transient popovers close when the user clicks elsewhere.
        popover.behavior = .transient
        popover.delegate = self
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        // A popover made key can outlive a switch to another app — clicking a window
        // that is already frontmost is not the "interaction elsewhere" that transient
        // behaviour watches for. Close it explicitly when Mectrics stops being active.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidResignActive),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
    }

    @objc private func applicationDidResignActive() {
        guard popover.isShown else { return }
        popover.performClose(nil)
    }

    /// Rebuilds the menu bar items from scratch based on the enabled modules.
    func rebuild() {
        for (_, item) in items { item.remove() }
        items.removeAll()
        compactHealthItem?.remove()
        compactHealthItem = nil

        if model.compactHealthEnabled {
            let healthItem = CompactHealthStatusItem()
            healthItem.onClick = { [weak self] in
                self?.toggleHealthPopover()
            }
            compactHealthItem = healthItem
        }
        for (id, component) in model.orderedEnabledItems {
            let statusItem = MetricStatusItem(id: id, component: component)
            statusItem.onClick = { [weak self] moduleID in
                self?.togglePopover(for: moduleID)
            }
            items["\(id.rawValue)|\(component.rawValue)"] = statusItem
        }
        refresh()
    }

    /// Updates the live values of all items.
    func refresh() {
        let accent = model.accentNSColor
        compactHealthItem?.update(model.compactHealthState)
        for statusItem in items.values {
            let id = statusItem.id
            let sample = model.latest[id]
            statusItem.update(
                visual: sample.map {
                    MenuBarText.visual(
                        for: id,
                        component: statusItem.component,
                        sample: $0
                    )
                },
                state: model.metricState(for: id, isEnabled: true),
                samples: model.history(id),
                accent: accent,
                showIcon: model.showMenuBarIcons
            )
        }
    }

    // MARK: - Popover

    private func togglePopover(for id: MetricID) {
        // Anchor on the module's first item (a module can have several).
        guard let button = items.values.first(where: { $0.id == id })?.item.button else { return }

        if popover.isShown && popoverModuleID == id {
            onDetailVisibilityChanged?(id, false)
            popover.performClose(nil)
            popoverModuleID = nil
            return
        }
        if let popoverModuleID {
            onDetailVisibilityChanged?(popoverModuleID, false)
        }

        let content = DetailPopoverView(model: model, moduleID: id)
        let host = NSHostingController(rootView: content.quietFocusRing())
        // Content height varies (top-processes list expands/collapses) — let SwiftUI
        // drive the popover size instead of pinning it.
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        popoverModuleID = id
        popoverIsHealth = false
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        popover.contentViewController?.view.window?.clearInitialFocus()
        onDetailVisibilityChanged?(id, true)
    }

    private func toggleHealthPopover() {
        guard let button = compactHealthItem?.item.button else { return }
        if popover.isShown && popoverIsHealth {
            popover.performClose(nil)
            popoverIsHealth = false
            return
        }
        if let popoverModuleID {
            onDetailVisibilityChanged?(popoverModuleID, false)
        }

        let host = NSHostingController(
            rootView: CompactHealthPopoverView(model: model).quietFocusRing()
        )
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        popoverModuleID = nil
        popoverIsHealth = true
        popover.animates =
            !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.show(
            relativeTo: button.bounds,
            of: button,
            preferredEdge: .minY
        )
        popover.contentViewController?.view.window?.makeKey()
        popover.contentViewController?.view.window?.clearInitialFocus()
    }

    func popoverDidClose(_ notification: Notification) {
        if let popoverModuleID {
            onDetailVisibilityChanged?(popoverModuleID, false)
        }
        popoverModuleID = nil
        popoverIsHealth = false
    }
}
