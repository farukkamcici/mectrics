import AppKit
import MetricsKit

/// Menü çubuğunda tek bir modülü temsil eden `NSStatusItem` sarmalayıcısı.
///
/// Canlı metin + sparkline'ı bir `NSImage`'e render edip butona atarız. Bu yaklaşım
/// (Stats de benzerini kullanır) alt-görünüm yerleşimi zahmeti olmadan piksel-hassas
/// çizim ve doğru menü-çubuğu görünüm uyumu (açık/koyu) sağlar.
final class MetricStatusItem: NSObject {
    let id: MetricID
    let item: NSStatusItem
    var onClick: ((MetricID) -> Void)?

    init(id: MetricID) {
        self.id = id
        self.item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        // Menü çubuğunda ⌘-drag ile taşındığında konum korunsun.
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

    /// Menü çubuğu göstergesini günceller.
    func update(text: String, samples: [Double], accent: NSColor, showSparkline: Bool) {
        item.button?.image = Self.render(
            text: text,
            samples: showSparkline ? samples : [],
            accent: accent,
            appearance: item.button?.effectiveAppearance ?? NSApp.effectiveAppearance
        )
    }

    // MARK: - Çizim

    private static let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
    private static let height: CGFloat = 18
    private static let sparkWidth: CGFloat = 26
    private static let gap: CGFloat = 5

    private static func render(text: String, samples: [Double], accent: NSColor,
                               appearance: NSAppearance) -> NSImage {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor
        ]
        let textSize = (text as NSString).size(withAttributes: attrs)
        let hasSpark = !samples.isEmpty
        let width = ceil(textSize.width) + (hasSpark ? gap + sparkWidth : 0)

        let image = NSImage(size: NSSize(width: max(width, 8), height: height))
        image.lockFocus()
        appearance.performAsCurrentDrawingAppearance {
            // Metin — dikey ortalı.
            let textY = (height - textSize.height) / 2
            (text as NSString).draw(at: NSPoint(x: 0, y: textY), withAttributes: attrs)

            // Sparkline.
            if hasSpark {
                drawSparkline(samples, in: NSRect(
                    x: ceil(textSize.width) + gap,
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

        // Dolgu (hafif).
        let fill = NSBezierPath()
        fill.move(to: NSPoint(x: rect.minX, y: rect.minY))
        for i in 0..<values.count { fill.line(to: point(i)) }
        fill.line(to: NSPoint(x: rect.maxX, y: rect.minY))
        fill.close()
        accent.withAlphaComponent(0.18).setFill()
        fill.fill()

        // Çizgi.
        let line = NSBezierPath()
        line.lineWidth = 1.2
        line.move(to: point(0))
        for i in 1..<values.count { line.line(to: point(i)) }
        accent.setStroke()
        line.stroke()
    }
}
