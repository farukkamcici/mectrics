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
                Text(range.localizedName)
                    .font(.caption.weight(.medium))
                Spacer()
                Text("Hourly average")
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
                    AreaMark(
                        x: .value("Time", point.timestamp),
                        yStart: .value("Baseline", 0),
                        yEnd: .value("Average", point.average)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                accent.opacity(ExperienceChart.fillOpacity),
                                accent.opacity(0.02)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Average", point.average)
                    )
                    .foregroundStyle(accent)
                    .lineStyle(StrokeStyle(
                        lineWidth: ExperienceChart.detailStrokeWidth,
                        lineJoin: .round
                    ))

                    if points.count == 1 {
                        PointMark(
                            x: .value("Time", point.timestamp),
                            y: .value("Average", point.average)
                        )
                        .foregroundStyle(accent)
                    }
                }
                .chartYScale(domain: 0...1)
                .chartYAxis(.hidden)
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

    private var axisFormat: Date.FormatStyle {
        switch range {
        case .day:
            return .dateTime.hour(.defaultDigits(amPM: .abbreviated))
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
