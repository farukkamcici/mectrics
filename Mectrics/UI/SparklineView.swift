import SwiftUI

/// Basit SwiftUI sparkline — popover ve panellerde geçmişi çizer.
struct SparklineView: View {
    let values: [Double]     // 0...1 normalize
    var accent: Color = .accentColor

    var body: some View {
        GeometryReader { geo in
            let maxV = max(values.max() ?? 1, 0.0001)
            let count = values.count
            ZStack {
                if count > 1 {
                    let path = linePath(in: geo.size, maxV: maxV, count: count)
                    path.fill(
                        LinearGradient(
                            colors: [accent.opacity(0.25), accent.opacity(0.02)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    strokePath(in: geo.size, maxV: maxV, count: count)
                        .stroke(accent, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                }
            }
        }
    }

    private func x(_ i: Int, width: CGFloat, count: Int) -> CGFloat {
        CGFloat(i) / CGFloat(max(count - 1, 1)) * width
    }

    private func y(_ i: Int, height: CGFloat, maxV: Double) -> CGFloat {
        height - CGFloat(values[i] / maxV) * height
    }

    private func strokePath(in size: CGSize, maxV: Double, count: Int) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: x(0, width: size.width, count: count),
                           y: y(0, height: size.height, maxV: maxV)))
        for i in 1..<count {
            p.addLine(to: CGPoint(x: x(i, width: size.width, count: count),
                                  y: y(i, height: size.height, maxV: maxV)))
        }
        return p
    }

    private func linePath(in size: CGSize, maxV: Double, count: Int) -> Path {
        var p = strokePath(in: size, maxV: maxV, count: count)
        p.addLine(to: CGPoint(x: size.width, y: size.height))
        p.addLine(to: CGPoint(x: 0, y: size.height))
        p.closeSubpath()
        return p
    }
}
