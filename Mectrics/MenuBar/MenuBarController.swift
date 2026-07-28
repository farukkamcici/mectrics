import AppKit
import SwiftUI
import MetricsKit

/// Menü çubuğu öğelerini oluşturur, günceller ve tıklamada detay popover'ını yönetir.
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

    /// Etkin modüllere göre menü çubuğu öğelerini sıfırdan kurar.
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

    /// Tüm öğelerin canlı değerlerini günceller.
    func refresh() {
        let accent = NSColor.controlAccentColor
        for (id, statusItem) in items {
            guard let sample = model.latest[id] else { continue }
            statusItem.update(
                text: MenuBarText.string(for: id, sample: sample),
                samples: model.history(id),
                accent: accent,
                showSparkline: MenuBarText.showsSparkline(id)
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
        popover.contentSize = NSSize(width: 300, height: 260)
        popoverModuleID = id
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
}
