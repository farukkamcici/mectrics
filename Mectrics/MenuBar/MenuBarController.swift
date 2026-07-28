import AppKit
import SwiftUI
import MetricsKit

/// Creates and updates the menu bar items and manages the detail popover on click.
@MainActor
final class MenuBarController {
    private let model: AppModel
    private var items: [MetricID: MetricStatusItem] = [:]
    private let popover = NSPopover()
    private var popoverModuleID: MetricID?

    init(model: AppModel) {
        self.model = model
        popover.behavior = .transient
        popover.animates = true
    }

    /// Rebuilds the menu bar items from scratch based on the enabled modules.
    func rebuild() {
        for (_, item) in items { item.remove() }
        items.removeAll()

        for id in model.orderedEnabledModules {
            let statusItem = MetricStatusItem(id: id)
            statusItem.onClick = { [weak self] moduleID in
                self?.togglePopover(for: moduleID)
            }
            items[id] = statusItem
        }
        refresh()
    }

    /// Updates the live values of all items.
    func refresh() {
        let accent = model.accentNSColor
        let compact = model.menuBarStyle == .compact
        for (id, statusItem) in items {
            guard let sample = model.latest[id] else { continue }
            let capable = MenuBarText.showsSparkline(id)
            // Compact style forces value-only; otherwise the per-module choice wins.
            let style: ModuleDisplayStyle = (compact || !capable) ? .value : model.displayStyle(for: id)
            statusItem.update(
                text: style == .graph ? "" : MenuBarText.string(for: id, sample: sample),
                samples: model.history(id),
                accent: accent,
                showSparkline: capable && style != .value
            )
        }
    }

    // MARK: - Popover

    private func togglePopover(for id: MetricID) {
        guard let button = items[id]?.item.button else { return }

        if popover.isShown && popoverModuleID == id {
            popover.performClose(nil)
            popoverModuleID = nil
            return
        }

        let content = DetailPopoverView(model: model, moduleID: id)
        popover.contentViewController = NSHostingController(rootView: content)
        popover.contentSize = NSSize(width: 290, height: DetailPopoverView.height(for: id))
        popoverModuleID = id
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
}
