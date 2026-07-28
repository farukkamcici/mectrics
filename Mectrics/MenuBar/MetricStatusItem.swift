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
///
/// Compactness: the Network module renders as two stacked lines (down over up) in a
/// small monospaced font, so it stays narrow instead of reserving room for a wide
/// "↓999.9M ↑999.9M" single line.
final class MetricStatusItem: NSObject {
    let id: MetricID
    let item: NSStatusItem
    var onClick: ((MetricID) -> Void)?

    /// Font used for this module's live text (small for the two-line network item).
    private let textFont: NSFont
    /// Fixed width reserved for the text slot, measured once from a worst-case template.
    private let reservedTextWidth: CGFloat

    init(id: MetricID) {
        self.id = id
        self.item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.textFont = Self.font(for: id)
        let template = Self.template(for: id) as NSString
        self.reservedTextWidth = ceil(template.size(withAttributes: [.font: textFont]).width)
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
            font: textFont,
            samples: showSparkline ? samples : [],
            accent: accent,
            reservedTextWidth: reservedTextWidth,
            appearance: item.button?.effectiveAppearance ?? NSApp.effectiveAppearance
        )
    }

    // MARK: - Layout templates

    /// Common-worst-case string per module, used to reserve a stable text width. For
    /// the two-line network item this is a single line (both lines are the same width).
    ///
    /// Deliberately sized for the *common* worst case ("99%", not "100%"): reserving
    /// the rare 100% case permanently pads every item with dead space. When a value
    /// does exceed the slot, the item grows for those samples and shrinks back
    /// (`textSlot = max(reserved, content)`), which beats always-wasted width.
    private static func template(for id: MetricID) -> String {
        switch id {
        case .network:   return "↓999M"
        case .battery:   return "100"   // batteries do sit at 100; ⚡ grows the item while charging
        case .bluetooth: return "BT99"
        case .sensors:   return "99°"
        case .fans:      return "9.9K"
        default:         return "99"
        }
    }

    /// Font per module: a small semibold font for the two-line network item, the
    /// standard menu-bar size for everything else.
    private static func font(for id: MetricID) -> NSFont {
        switch id {
        case .network: return .monospacedDigitSystemFont(ofSize: 8.5, weight: .semibold)
        default:       return .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        }
    }

    // MARK: - Drawing

    private static let height: CGFloat = 20
    private static let sparkWidth: CGFloat = 20
    private static let gap: CGFloat = 4

    private static func render(text: String, font: NSFont, samples: [Double], accent: NSColor,
                               reservedTextWidth: CGFloat,
                               appearance: NSAppearance) -> NSImage {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor
        ]

        let lines = text.components(separatedBy: "\n")
        let isTwoLine = lines.count > 1
        // Graph-only style: no text slot, just a slightly wider sparkline.
        let graphOnly = text.isEmpty

        // Measure the widest line so the slot never shrinks below real content.
        let lineWidths = lines.map { ceil(($0 as NSString).size(withAttributes: attrs).width) }
        let contentWidth = lineWidths.max() ?? 0
        let textSlot = graphOnly ? 0 : max(reservedTextWidth, contentWidth)

        let hasSpark = !samples.isEmpty && !isTwoLine
        let sparkW = graphOnly ? sparkWidth + 8 : sparkWidth
        let width = textSlot + (hasSpark ? (graphOnly ? sparkW : gap + sparkW) : 0)

        let image = NSImage(size: NSSize(width: max(width, 8), height: height))
        image.lockFocus()
        appearance.performAsCurrentDrawingAppearance {
            if isTwoLine {
                // Two stacked lines, each right-aligned to the slot's right edge so the
                // right side (and any following item) never moves as digits change.
                drawRightAligned(lines[0], attrs: attrs, slot: textSlot, baselineY: height * 0.5)
                drawRightAligned(lines[1], attrs: attrs, slot: textSlot, baselineY: 0)
            } else {
                if !graphOnly {
                    let textSize = (text as NSString).size(withAttributes: attrs)
                    let textY = (height - textSize.height) / 2
                    drawRightAligned(text, attrs: attrs, slot: textSlot, baselineY: textY)
                }

                if hasSpark {
                    drawSparkline(samples, in: NSRect(
                        x: graphOnly ? 0 : textSlot + gap,
                        y: 3,
                        width: sparkW,
                        height: height - 6
                    ), accent: accent)
                }
            }
        }
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    /// Draws `text` right-aligned so its right edge sits at `slot`.
    private static func drawRightAligned(_ text: String, attrs: [NSAttributedString.Key: Any],
                                         slot: CGFloat, baselineY: CGFloat) {
        let size = (text as NSString).size(withAttributes: attrs)
        let x = slot - ceil(size.width)
        (text as NSString).draw(at: NSPoint(x: x, y: baselineY), withAttributes: attrs)
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
        line.lineJoinStyle = .round
        line.move(to: point(0))
        for i in 1..<values.count { line.line(to: point(i)) }
        accent.setStroke()
        line.stroke()
    }
}
