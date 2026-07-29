import AppKit
import MetricsKit

/// Wraps a single `NSStatusItem` representing one module in the menu bar.
///
/// The live content is rendered into an `NSImage` assigned to the button (Stats uses
/// a similar approach). This gives pixel-precise drawing and correct light/dark
/// menu-bar adaptation without any subview layout work.
///
/// Width stability: text-bearing components reserve a fixed text width derived from a
/// worst-case template, and the actual text is right-aligned inside that slot.
/// Pictorial components (battery glyph, ring, core bars) have inherently fixed sizes.
final class MetricStatusItem: NSObject {
    let id: MetricID
    let component: MenuBarComponent
    let item: NSStatusItem
    var onClick: ((MetricID) -> Void)?

    private let textFont: NSFont
    private let reservedTextWidth: CGFloat
    /// Base (untinted) SF Symbol for the optional embedded module icon.
    private let iconSymbol: NSImage?

    init(id: MetricID, component: MenuBarComponent) {
        self.id = id
        self.component = component
        self.item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // The stacked network activity item uses a small two-line font.
        self.textFont = component == .netActivity
            ? .monospacedDigitSystemFont(ofSize: 8.5, weight: .semibold)
            : .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let template = component.template(for: id)
        self.reservedTextWidth = template.isEmpty ? 0
            : ceil((template as NSString).size(withAttributes: [.font: textFont]).width)
        self.iconSymbol = NSImage(
            systemSymbolName: MetricSymbol.name(for: id),
            accessibilityDescription: nil
        )?.withSymbolConfiguration(.init(pointSize: 10.5, weight: .semibold))
        super.init()
        // Preserve position when the user ⌘-drags the item in the menu bar.
        item.autosaveName = "mectrics.\(id.rawValue).\(component.rawValue)"
        // Removing an autosave-named item persists a hidden flag; force visible so
        // re-adding an item (menu bar rebuild) always shows it again.
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

    /// Updates the menu-bar indicator without changing its state-specific width.
    func update(
        visual: MenuBarVisual?,
        state: MetricDataState,
        samples: [Double],
        accent: NSColor,
        showIcon: Bool
    ) {
        guard let button = item.button else { return }
        button.image = Self.render(
            visual: visual,
            state: state,
            component: component,
            font: textFont,
            samples: samples,
            accent: accent,
            reservedTextWidth: reservedTextWidth,
            icon: (showIcon && !component.drawsModuleGlyph) ? iconSymbol : nil,
            appearance: button.effectiveAppearance
        )
        button.setAccessibilityLabel(
            String(
                localized: "menuBar.component.accessibilityLabel",
                defaultValue: "\(id.localizedName), \(component.localizedName)"
            )
        )
        button.setAccessibilityValue(Self.accessibilityValue(for: visual, state: state))
    }

    // MARK: - Drawing

    private static let height: CGFloat = 20
    private static let sparkWidth: CGFloat = 20
    private static let gap: CGFloat = 4

    /// Leading space taken by the embedded module icon (glyph + gap).
    private static let iconSlot: CGFloat = 16

    private static let batteryWidth: CGFloat = 25
    /// Wide enough for a three-digit charge inside the body at `batteryLabelFont`.
    private static let batteryLabeledWidth: CGFloat = 32
    private static let batteryLabelFont = NSFont.monospacedDigitSystemFont(
        ofSize: 7.5,
        weight: .bold
    )

    private static func render(visual: MenuBarVisual?, state: MetricDataState,
                               component: MenuBarComponent, font: NSFont, samples: [Double],
                               accent: NSColor, reservedTextWidth: CGFloat,
                               icon: NSImage?, appearance: NSAppearance) -> NSImage {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor
        ]

        // Resolve content width per visual.
        let contentWidth: CGFloat
        if let visual {
            contentWidth = width(
                for: visual,
                reservedTextWidth: reservedTextWidth,
                attributes: attrs
            )
        } else {
            contentWidth = fallbackWidth(
                for: component,
                reservedTextWidth: reservedTextWidth
            )
        }

        let offset: CGFloat = icon != nil ? iconSlot : 0
        let width = offset + contentWidth

        let image = NSImage(size: NSSize(width: max(width, 8), height: height))
        image.lockFocus()
        appearance.performAsCurrentDrawingAppearance {
            if let icon { drawIcon(icon, accent: accent) }
            if let visual {
                switch visual {
                case .text(let text):
                    drawTextBlock(text, attrs: attrs,
                                  slot: offset + textSlot(text, reservedTextWidth, attrs))
                case .textGraph(let text):
                    let slot = offset + textSlot(text, reservedTextWidth, attrs)
                    drawTextBlock(text, attrs: attrs, slot: slot)
                    drawSparkline(samples, in: NSRect(x: slot + gap, y: 3,
                                                      width: sparkWidth, height: height - 6),
                                  accent: accent)
                case .coreBars(let values):
                    drawCoreBars(values, in: NSRect(x: offset, y: 3,
                                                    width: contentWidth, height: height - 6),
                                 accent: accent)
                case .battery(let level, let charging, let showsPercent):
                    drawBattery(level: level, charging: charging,
                                showsPercent: showsPercent,
                                in: NSRect(x: offset, y: 0, width: contentWidth, height: height))
                case .ring(let fraction):
                    drawRing(fraction, in: NSRect(x: offset + 1, y: (height - 14) / 2,
                                                  width: 14, height: 14),
                             accent: accent)
                }
            } else {
                drawState(
                    state,
                    in: NSRect(x: offset, y: 0, width: contentWidth, height: height),
                    compact: false
                )
            }
            if visual != nil && state != .live {
                drawState(
                    state,
                    in: NSRect(x: offset, y: 0, width: contentWidth, height: height),
                    compact: true
                )
            }
        }
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private static func width(
        for visual: MenuBarVisual,
        reservedTextWidth: CGFloat,
        attributes: [NSAttributedString.Key: Any]
    ) -> CGFloat {
        switch visual {
        case .text(let text):
            return textSlot(text, reservedTextWidth, attributes)
        case .textGraph(let text):
            return textSlot(text, reservedTextWidth, attributes) + gap + sparkWidth
        case .coreBars(let values):
            return CGFloat(max(values.count, 2)) * 4
        case .battery(_, _, let showsPercent):
            return showsPercent ? batteryLabeledWidth : batteryWidth
        case .ring:
            return 16
        }
    }

    private static func fallbackWidth(
        for component: MenuBarComponent,
        reservedTextWidth: CGFloat
    ) -> CGFloat {
        switch component {
        case .valueGraph:
            return reservedTextWidth + gap + sparkWidth
        case .coreBars:
            return CGFloat(max(ProcessInfo.processInfo.processorCount, 2)) * 4
        case .batteryIcon:
            return batteryWidth
        case .batteryIconValue:
            return batteryLabeledWidth
        case .ring:
            return 16
        default:
            return max(reservedTextWidth, 12)
        }
    }

    private static func accessibilityValue(
        for visual: MenuBarVisual?,
        state: MetricDataState
    ) -> String {
        let stateName = state.localizedName
        guard let visual else { return stateName }
        switch visual {
        case .text(let text), .textGraph(let text):
            return "\(text.replacingOccurrences(of: "\n", with: " ")), \(stateName)"
        default:
            return stateName
        }
    }

    private static func drawState(
        _ state: MetricDataState,
        in rect: NSRect,
        compact: Bool
    ) {
        let pointSize: CGFloat = compact ? 7 : 10
        guard let image = NSImage(
            systemSymbolName: state.symbolName,
            accessibilityDescription: nil
        )?.withSymbolConfiguration(.init(pointSize: pointSize, weight: .semibold))
        else { return }

        let size = image.size
        let origin = compact
            ? NSPoint(x: rect.maxX - size.width, y: rect.maxY - size.height)
            : NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2)
        image.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
        stateNSColor(state).set()
        NSRect(origin: origin, size: size).fill(using: .sourceAtop)
    }

    private static func stateNSColor(_ state: MetricDataState) -> NSColor {
        switch state {
        case .live:
            return .systemGreen
        case .stale, .permissionRequired:
            return .systemOrange
        case .error:
            return .systemRed
        case .collecting, .unavailable, .disabled:
            return .secondaryLabelColor
        }
    }

    /// Draws the module symbol tinted with the accent color, vertically centered at
    /// the leading edge — icons match the sparklines/charts and pop against the text.
    private static func drawIcon(_ icon: NSImage, accent: NSColor) {
        let size = icon.size
        let origin = NSPoint(x: 0, y: (height - size.height) / 2)
        icon.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
        accent.set()
        NSRect(origin: origin, size: size).fill(using: .sourceAtop)
    }

    /// Text remains inside the invariant slot. Templates are deliberately sized for
    /// the widest output of each formatter.
    private static func textSlot(_ text: String, _ reserved: CGFloat,
                                 _ attrs: [NSAttributedString.Key: Any]) -> CGFloat {
        let widest = text.components(separatedBy: "\n")
            .map { ceil(($0 as NSString).size(withAttributes: attrs).width) }
            .max() ?? 0
        assert(
            widest <= reserved + 0.5,
            "Menu bar template is too narrow for \(text)"
        )
        return reserved
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
    private static func drawBattery(
        level: Double,
        charging: Bool,
        showsPercent: Bool,
        in rect: NSRect
    ) {
        let body = NSRect(
            x: rect.minX + 0.5,
            y: rect.midY - 5.5,
            width: rect.width - 4,
            height: 11
        )
        let outline = NSBezierPath(roundedRect: body, xRadius: 3, yRadius: 3)
        outline.lineWidth = 1.2
        NSColor.labelColor.withAlphaComponent(0.75).setStroke()
        outline.stroke()

        // Terminal nub.
        let nub = NSRect(x: body.maxX + 1, y: body.midY - 2, width: 2, height: 4)
        NSColor.labelColor.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: nub, xRadius: 1, yRadius: 1).fill()

        // Proportional fill; red when critically low.
        let inset = body.insetBy(dx: 1.8, dy: 1.8)
        let clamped = min(max(level, 0), 1)
        let fillRect = NSRect(x: inset.minX, y: inset.minY,
                              width: inset.width * CGFloat(clamped), height: inset.height)
        (clamped <= 0.2 && !charging ? NSColor.systemRed : NSColor.labelColor.withAlphaComponent(0.9)).setFill()
        NSBezierPath(roundedRect: fillRect, xRadius: 1.5, yRadius: 1.5).fill()

        if showsPercent {
            drawBatteryCharge(
                percent: Int((clamped * 100).rounded()),
                in: body,
                over: fillRect
            )
        }

        if charging {
            let bolt = "⚡" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 8, weight: .bold),
                .foregroundColor: NSColor.labelColor
            ]
            let size = bolt.size(withAttributes: attrs)
            // Charging moves the bolt off the label rather than over it.
            let x = showsPercent ? body.maxX - size.width - 1 : body.midX - size.width / 2
            bolt.draw(at: NSPoint(x: x, y: body.midY - size.height / 2),
                      withAttributes: attrs)
        }
    }

    /// Draws the charge inside the battery the way macOS does: solid where the body is
    /// empty, and knocked out of the fill where it is not.
    ///
    /// A single colour cannot work here — the digits straddle the boundary between
    /// filled and empty as the charge drops, so any fixed colour disappears against one
    /// side or the other. Cutting them out of the fill instead lets the menu bar behind
    /// show through, which keeps the same contrast at every level and in both
    /// appearances.
    private static func drawBatteryCharge(
        percent: Int,
        in body: NSRect,
        over fillRect: NSRect
    ) {
        let text = "\(percent)" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: batteryLabelFont,
            .foregroundColor: NSColor.labelColor
        ]
        let size = text.size(withAttributes: attributes)
        let origin = NSPoint(
            x: body.midX - size.width / 2,
            y: body.midY - size.height / 2
        )

        guard let context = NSGraphicsContext.current else { return }

        // Where the body is empty: ordinary digits.
        context.saveGraphicsState()
        let empty = NSBezierPath(rect: body)
        empty.append(NSBezierPath(rect: fillRect))
        empty.windingRule = .evenOdd
        empty.setClip()
        text.draw(at: origin, withAttributes: attributes)
        context.restoreGraphicsState()

        // Where it is filled: remove the digits from the fill.
        context.saveGraphicsState()
        NSBezierPath(rect: fillRect).setClip()
        context.compositingOperation = .destinationOut
        text.draw(at: origin, withAttributes: attributes)
        context.restoreGraphicsState()
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
