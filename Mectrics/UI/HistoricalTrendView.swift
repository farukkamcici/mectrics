import Charts
import SwiftUI
import MetricsKit

/// Compact hourly history for slow-changing capacity metrics.
struct HistoricalTrendView: View {
    let points: [HistoricalMetricPoint]
    let range: DetailHistoryRange
    let metricName: String
    var accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xSmall) {
            HStack {
                Text(rangeLabel)
                    .font(.caption.weight(.medium))
                Spacer()
                Text(readingCountText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if points.isEmpty {
                Label("History builds hourly as Mectrics runs.", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 58)
            } else {
                Chart(points, id: \.timestamp) { point in
                    LineMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Average", point.average)
                    )
                    .foregroundStyle(accent)
                    .lineStyle(StrokeStyle(
                        lineWidth: ExperienceChart.detailStrokeWidth,
                        lineJoin: .round
                    ))

                    if points.count <= 24 {
                        PointMark(
                            x: .value("Time", point.timestamp),
                            y: .value("Average", point.average)
                        )
                        .foregroundStyle(accent)
                        .symbolSize(18)
                    }
                }
                .chartYScale(domain: yDomain)
                .chartYAxis {
                    AxisMarks(
                        position: .trailing,
                        values: [yDomain.lowerBound, yDomain.upperBound]
                    ) { value in
                        AxisGridLine()
                            .foregroundStyle(.secondary.opacity(
                                ExperienceChart.separatorOpacity
                            ))
                        AxisValueLabel {
                            if let reading = value.as(Double.self) {
                                Text(
                                    reading,
                                    format: .percent.precision(.fractionLength(0))
                                )
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                        AxisGridLine()
                            .foregroundStyle(.secondary.opacity(
                                ExperienceChart.separatorOpacity
                            ))
                        AxisTick()
                        AxisValueLabel(format: axisFormat)
                    }
                }
                .frame(height: 72)
                .accessibilityLabel(
                    String(
                        localized: "history.chart.accessibilityLabel",
                        defaultValue: "\(metricName) history, \(range.localizedName)"
                    )
                )
                .accessibilityValue(accessibilitySummary)
            }
        }
    }

    /// A labelled, minimum ten-point percentage window makes slow disk changes
    /// legible without implying that the chart starts at zero.
    private var yDomain: ClosedRange<Double> {
        guard let minimum = points.map(\.minimum).min(),
              let maximum = points.map(\.maximum).max() else {
            return 0...1
        }
        let minimumSpan = 0.1
        let dataSpan = maximum - minimum
        let targetSpan = max(minimumSpan, dataSpan * 1.5)
        let center = (minimum + maximum) / 2
        var lower = max(0, center - targetSpan / 2)
        var upper = min(1, center + targetSpan / 2)
        if upper - lower < minimumSpan {
            if lower == 0 {
                upper = min(1, minimumSpan)
            } else {
                lower = max(0, upper - minimumSpan)
            }
        }
        return lower...upper
    }

    private var rangeLabel: String {
        let format = String(
            localized: "history.chart.range",
            defaultValue: "Up to %@"
        )
        return String(format: format, range.localizedName)
    }

    private var readingCountText: String {
        let format = String(
            localized: "history.chart.readingCount",
            defaultValue: "%lld hourly readings"
        )
        return String(format: format, Int64(points.count))
    }

    private var axisFormat: Date.FormatStyle {
        switch range {
        case .day:
            return .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
        case .week, .month:
            return .dateTime.month(.abbreviated).day()
        }
    }

    private var accessibilitySummary: String {
        guard let minimum = points.map(\.minimum).min(),
              let maximum = points.map(\.maximum).max(),
              let latest = points.last?.average else {
            return String(localized: "chart.noReadings", defaultValue: "No readings")
        }
        let format = String(
            localized: "history.chart.summary",
            defaultValue: "%lld hourly readings, minimum %.0f%%, maximum %.0f%%, latest %.0f%%"
        )
        return String(
            format: format,
            Int64(points.count),
            minimum * 100,
            maximum * 100,
            latest * 100
        )
    }
}
