import AppKit
import MetricsKit

/// Wraps a single `NSStatusItem` representing one module in the menu bar.
///
/// The live content is rendered into an `NSImage` assigned to the button (Stats uses
/// a similar approach). This gives pixel-precise drawing and correct light/dark
/// menu-bar adaptation without any subview layout work.
///
/// Width stability: text-bearing components reserve a FIXED text width derived from a
/// common-worst-case template ("99%", not "100%"), and the actual text is
/// right-aligned inside that slot. When a value does exceed the slot the item grows
/// for those samples and shrinks back — rare jitter beats always-wasted width.
/// Pictorial components (battery glyph, ring, core bars) have inherently fixed sizes.
final class MetricStatusItem: NSObject {
    let id: MetricID
    let item: NSStatusItem
    var onClick: ((MetricID) -> Void)?

    /// Component-dependent cache: font + reserved slot are re-measured only when the
    /// user switches this module's component.
    private var cachedComponent: MenuBarComponent?
    private var textFont: NSFont = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
    private var reservedTextWidth: CGFloat = 0

    init(id: MetricID) {
        self.id = id
        self.item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        // Preserve position when the user ⌘-drags the item in the menu bar.
        item.autosaveName = "mectrics.\(id.rawValue)"
        // Removing an autosave-named item persists a hidden flag; force visible so
        // re-adding a module (menu bar rebuild) always shows it again.
        item.isVisible = true
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
    func update(component: MenuBarComponent, visual: MenuBarVisual,
                samples: [Double], accent: NSColor) {
        if component != cachedComponent {
            cachedComponent = component
            // The stacked network activity item uses a small two-line font.
            textFont = component == .netActivity
                ? .monospacedDigitSystemFont(ofSize: 8.5, weight: .semibold)
                : .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            let template = component.template(for: id)
            reservedTextWidth = template.isEmpty ? 0
                : ceil((template as NSString).size(withAttributes: [.font: textFont]).width)
        }
        item.button?.image = Self.render(
            visual: visual,
            font: textFont,
            samples: samples,
            accent: accent,
            reservedTextWidth: reservedTextWidth,
            appearance: item.button?.effectiveAppearance ?? NSApp.effectiveAppearance
        )
    }

    // MARK: - Drawing

    private static let height: CGFloat = 20
    private static let sparkWidth: CGFloat = 20
    private static let gap: CGFloat = 4

    private static func render(visual: MenuBarVisual, font: NSFont, samples: [Double],
                               accent: NSColor, reservedTextWidth: CGFloat,
                               appearance: NSAppearance) -> NSImage {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor
        ]

        // Resolve content width per visual.
        let width: CGFloat
        switch visual {
        case .text(let text):
            width = textSlot(text, reservedTextWidth, attrs)
        case .textGraph(let text):
            width = textSlot(text, reservedTextWidth, attrs) + gap + sparkWidth
        case .graph:
            width = sparkWidth + 8
        case .coreBars(let values):
            width = CGFloat(max(values.count, 2)) * 4
        case .battery:
            width = 25
        case .ring:
            width = 16
        }

        let image = NSImage(size: NSSize(width: max(width, 8), height: height))
        image.lockFocus()
        appearance.performAsCurrentDrawingAppearance {
            switch visual {
            case .text(let text):
                drawTextBlock(text, attrs: attrs, slot: textSlot(text, reservedTextWidth, attrs))
            case .textGraph(let text):
                let slot = textSlot(text, reservedTextWidth, attrs)
                drawTextBlock(text, attrs: attrs, slot: slot)
                drawSparkline(samples, in: NSRect(x: slot + gap, y: 3,
                                                  width: sparkWidth, height: height - 6),
                              accent: accent)
            case .graph:
                drawSparkline(samples, in: NSRect(x: 0, y: 3,
                                                  width: sparkWidth + 8, height: height - 6),
                              accent: accent)
            case .coreBars(let values):
                drawCoreBars(values, in: NSRect(x: 0, y: 3, width: width, height: height - 6),
                             accent: accent)
            case .battery(let level, let charging):
                drawBattery(level: level, charging: charging,
                            in: NSRect(x: 0, y: 0, width: width, height: height))
            case .ring(let fraction):
                drawRing(fraction, in: NSRect(x: 1, y: (height - 14) / 2, width: 14, height: 14),
                         accent: accent)
            }
        }
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    /// Slot width for a text: the reserved template width, grown if the actual
    /// content is wider (rare 100% moments).
    private static func textSlot(_ text: String, _ reserved: CGFloat,
                                 _ attrs: [NSAttributedString.Key: Any]) -> CGFloat {
        let widest = text.components(separatedBy: "\n")
            .map { ceil(($0 as NSString).size(withAttributes: attrs).width) }
            .max() ?? 0
        return max(reserved, widest)
    }

    /// Single- or two-line right-aligned text (two-line = stacked network rates).
    private static func drawTextBlock(_ text: String, attrs: [NSAttributedString.Key: Any],
                                      slot: CGFloat) {
        let lines = text.components(separatedBy: "\n")
        if lines.count > 1 {
            drawRightAligned(lines[0], attrs: attrs, slot: slot, baselineY: height * 0.5)
            drawRightAligned(lines[1], attrs: attrs, slot: slot, baselineY: 0)
        } else {
            let textSize = (text as NSString).size(withAttributes: attrs)
            drawRightAligned(text, attrs: attrs, slot: slot, baselineY: (height - textSize.height) / 2)
        }
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
        accent.withAlphaComponent(0.2).setFill()
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

    /// One 3pt-wide bar per CPU core over a faint full-height track.
    private static func drawCoreBars(_ values: [Double], in rect: NSRect, accent: NSColor) {
        guard !values.isEmpty else { return }
        let barWidth: CGFloat = 3
        for (i, value) in values.enumerated() {
            let x = rect.minX + CGFloat(i) * 4
            let track = NSRect(x: x, y: rect.minY, width: barWidth, height: rect.height)
            NSColor.labelColor.withAlphaComponent(0.14).setFill()
            NSBezierPath(roundedRect: track, xRadius: 1, yRadius: 1).fill()

            let h = max(1.5, CGFloat(min(max(value, 0), 1)) * rect.height)
            let bar = NSRect(x: x, y: rect.minY, width: barWidth, height: h)
            accent.setFill()
            NSBezierPath(roundedRect: bar, xRadius: 1, yRadius: 1).fill()
        }
    }

    /// Classic battery glyph with a proportional fill and a bolt while charging.
    private static func drawBattery(level: Double, charging: Bool, in rect: NSRect) {
        let body = NSRect(x: rect.minX + 0.5, y: rect.midY - 5, width: rect.width - 4, height: 10)
        let outline = NSBezierPath(roundedRect: body, xRadius: 2.5, yRadius: 2.5)
        outline.lineWidth = 1
        NSColor.labelColor.withAlphaComponent(0.55).setStroke()
        outline.stroke()

        // Terminal nub.
        let nub = NSRect(x: body.maxX + 1, y: body.midY - 2, width: 2, height: 4)
        NSColor.labelColor.withAlphaComponent(0.55).setFill()
        NSBezierPath(roundedRect: nub, xRadius: 1, yRadius: 1).fill()

        // Proportional fill; red when critically low.
        let inset = body.insetBy(dx: 1.5, dy: 1.5)
        let clamped = min(max(level, 0), 1)
        let fillRect = NSRect(x: inset.minX, y: inset.minY,
                              width: inset.width * CGFloat(clamped), height: inset.height)
        (clamped <= 0.2 && !charging ? NSColor.systemRed : NSColor.labelColor.withAlphaComponent(0.85)).setFill()
        NSBezierPath(roundedRect: fillRect, xRadius: 1.5, yRadius: 1.5).fill()

        if charging {
            let bolt = "⚡" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 8, weight: .bold),
                .foregroundColor: NSColor.labelColor
            ]
            let size = bolt.size(withAttributes: attrs)
            bolt.draw(at: NSPoint(x: body.midX - size.width / 2, y: body.midY - size.height / 2),
                      withAttributes: attrs)
        }
    }

    /// Fraction donut (disk usage): faint full track + accent arc from 12 o'clock.
    private static func drawRing(_ fraction: Double, in rect: NSRect, accent: NSColor) {
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let radius = rect.width / 2 - 1.5

        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        track.lineWidth = 2.5
        NSColor.labelColor.withAlphaComponent(0.18).setStroke()
        track.stroke()

        let clamped = min(max(fraction, 0), 1)
        guard clamped > 0.01 else { return }
        let arc = NSBezierPath()
        // Start at 12 o'clock (90°) and sweep clockwise.
        arc.appendArc(withCenter: center, radius: radius,
                      startAngle: 90, endAngle: 90 - CGFloat(clamped) * 360, clockwise: true)
        arc.lineWidth = 2.5
        arc.lineCapStyle = .round
        accent.setStroke()
        arc.stroke()
    }
}
