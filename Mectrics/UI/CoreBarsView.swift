import SwiftUI

/// One vertical bar per CPU core (0...1), bottom-aligned — the "cores load" strip
/// shown in the CPU popover.
struct CoreBarsView: View {
    let values: [Double]
    var accent: Color = .accentColor

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .bottom, spacing: ExperienceSpacing.xSmall) {
                ForEach(values.indices, id: \.self) { i in
                    VStack {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: ExperienceRadius.micro)
                            .fill(accent.opacity(0.9))
                            .frame(height: max(2, min(values[i], 1) * geo.size.height))
                    }
                    .background(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: ExperienceRadius.micro)
                            .fill(.secondary.opacity(0.15))
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            String(localized: "cores.chart.label", defaultValue: "Processor core usage")
        )
        .accessibilityValue(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        guard let minimum = values.min(),
              let maximum = values.max() else {
            return String(localized: "chart.noReadings", defaultValue: "No readings")
        }
        let format = String(
            localized: "cores.chart.summary",
            defaultValue: "%lld cores, minimum %.0f%%, maximum %.0f%%"
        )
        return String(format: format, Int64(values.count), minimum * 100, maximum * 100)
    }
}
