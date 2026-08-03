import XCTest
@testable import MetricsKit

/// The store is written every sampling cycle and read by every chart. This benchmark
/// catches regressions that reintroduce hot-path allocation or expensive locking.
final class PerformanceRegressionTests: XCTestCase {
    func testMetricStoreHotPathPerformance() {
        let store = MetricStore(capacity: 90)
        store.append(MetricSample(value: 0), for: .cpu)
        var latestValue = 0.0

        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()]) {
            for index in 0..<20_000 {
                store.append(
                    MetricSample(
                        timestamp: Date(timeIntervalSinceReferenceDate: Double(index)),
                        value: Double(index % 100) / 100
                    ),
                    for: .cpu
                )
                if index.isMultiple(of: 20) {
                    latestValue = store.latest(.cpu)?.value ?? 0
                    _ = store.history(.cpu, count: 40)
                }
            }
        }

        XCTAssertGreaterThanOrEqual(latestValue, 0)
    }
}
