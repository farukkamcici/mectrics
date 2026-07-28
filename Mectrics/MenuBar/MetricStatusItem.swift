import AppKit
import MetricsKit

/// Wraps a single `NSStatusItem` representing one module in the menu bar.
///
/// The live text + sparkline are rendered into an `NSImage` assigned to the button
/// (Stats uses a similar approach). This gives pixel-precise drawing and correct
/// light/dark menu-bar adaptation without any subview layout work.
///
/// Width stability: each module reserves a FIXED text width derived from a worst-case
/// template string, and the actual text is right-aligned inside that slot. This keeps
/// the item's total width constant so items never shift as values change digits
/// (e.g. "9%" -> "100%", or network rates growing/shrinking).
final class MetricStatusItem: NSObject {
    let id: MetricID
    let item: NSStatusItem
    var onClick: ((MetricID) -> Void)?

    /// Fixed width reserved for the text slot, measured once from a worst-case template.
    private let reservedTextWidth: CGFloat

    init(id: MetricID) {
        self.id = id
        self.item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let template = Self.template(for: id) as NSString
        self.reservedTextWidth = ceil(template.size(withAttributes: [.font: Self.font]).width)
        super.init()
        // Preserve position when the user ⌘-drags the item in the menu bar.
        item.autosaveName = "mectrics.\(id.rawValue)"
        if let button = item.button {
            button.target = self
            button.action = #selector(clicked)
            button.imagePosition = .imageOnly
        }
    }

    @objc private func clicked() {
        onClick?(id)
    }

    func remove() {
        NSStatusBar.system.removeStatusItem(item)
    }

    /// Updates the live menu-bar indicator.
    func update(text: String, samples: [Double], accent: NSColor, showSparkline: Bool) {
        item.button?.image = Self.render(
            text: text,
            samples: showSparkline ? samples : [],
            accent: accent,
            reservedTextWidth: reservedTextWidth,
            appearance: item.button?.effectiveAppearance ?? NSApp.effectiveAppearance
        )
    }

    // MARK: - Layout templates

    /// Worst-case string per module, used to reserve a stable text width.
    private static func template(for id: MetricID) -> String {
        switch id {
        case .network:   return "↓999.9M ↑999.9M"
        case .battery:   return "⚡100%"
        case .bluetooth: return "BT 100%"
        default:         return "100%"
        }
    }

    // MARK: - Drawing

    private static let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
    private static let height: CGFloat = 18
    private static let sparkWidth: CGFloat = 26
    private static let gap: CGFloat = 5

    private static func render(text: String, samples: [Double], accent: NSColor,
                               reservedTextWidth: CGFloat,
                               appearance: NSAppearance) -> NSImage {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor
        ]
        let textSize = (text as NSString).size(withAttributes: attrs)
        let hasSpark = !samples.isEmpty
        // Text slot is fixed; the item width never depends on the current digit count.
        let textSlot = max(reservedTextWidth, ceil(textSize.width))
        let width = textSlot + (hasSpark ? gap + sparkWidth : 0)

        let image = NSImage(size: NSSize(width: max(width, 8), height: height))
        image.lockFocus()
        appearance.performAsCurrentDrawingAppearance {
            // Right-align text within the reserved slot so the right edge (and the
            // sparkline after it) stays put while leading digits grow leftward.
            let textX = textSlot - ceil(textSize.width)
            let textY = (height - textSize.height) / 2
            (text as NSString).draw(at: NSPoint(x: textX, y: textY), withAttributes: attrs)

            if hasSpark {
                drawSparkline(samples, in: NSRect(
                    x: textSlot + gap,
                    y: 2,
                    width: sparkWidth,
                    height: height - 4
                ), accent: accent)
            }
        }
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private static func drawSparkline(_ values: [Double], in rect: NSRect, accent: NSColor) {
        guard values.count > 1 else { return }
        let maxV = max(values.max() ?? 1, 0.0001)
        let stepX = rect.width / CGFloat(values.count - 1)

        func point(_ i: Int) -> NSPoint {
            let x = rect.minX + CGFloat(i) * stepX
            let y = rect.minY + CGFloat(values[i] / maxV) * rect.height
            return NSPoint(x: x, y: min(max(y, rect.minY), rect.maxY))
        }

        // Light fill under the curve.
        let fill = NSBezierPath()
        fill.move(to: NSPoint(x: rect.minX, y: rect.minY))
        for i in 0..<values.count { fill.line(to: point(i)) }
        fill.line(to: NSPoint(x: rect.maxX, y: rect.minY))
        fill.close()
        accent.withAlphaComponent(0.18).setFill()
        fill.fill()

        // Line.
        let line = NSBezierPath()
        line.lineWidth = 1.2
        line.move(to: point(0))
        for i in 1..<values.count { line.line(to: point(i)) }
        accent.setStroke()
        line.stroke()
    }
}
