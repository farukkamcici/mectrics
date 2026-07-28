import SwiftUI

/// One vertical bar per CPU core (0...1), bottom-aligned — the "cores load" strip
/// shown in the CPU popover.
struct CoreBarsView: View {
    let values: [Double]
    var accent: Color = .accentColor

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(values.indices, id: \.self) { i in
                    VStack {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(accent.opacity(0.9))
                            .frame(height: max(2, min(values[i], 1) * geo.size.height))
                    }
                    .background(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(.secondary.opacity(0.15))
                    }
                }
            }
        }
    }
}
