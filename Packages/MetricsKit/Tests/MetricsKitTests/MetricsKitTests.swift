import XCTest
@testable import MetricsKit

final class MetricsKitTests: XCTestCase {

    // MARK: - RingBuffer / MetricStore

    func testStoreKeepsMostRecentWithinCapacity() {
        let store = MetricStore(capacity: 3)
        for i in 0..<5 {
            store.append(MetricSample(value: Double(i)), for: .cpu)
        }
        let hist = store.history(.cpu)
        XCTAssertEqual(hist.count, 3)
        XCTAssertEqual(hist.map(\.value), [2, 3, 4]) // newest 3 samples, in order
        XCTAssertEqual(store.latest(.cpu)?.value, 4)
    }

    func testHistoryCountSuffix() {
        let store = MetricStore(capacity: 100)
        for i in 0..<10 {
            store.append(MetricSample(value: Double(i)), for: .memory)
        }
        XCTAssertEqual(store.history(.memory, count: 3).map(\.value), [7, 8, 9])
    }

    // MARK: - Formatting

    func testPercentFormat() {
        XCTAssertEqual(MetricFormat.percent(0.5), "50%")
        XCTAssertEqual(MetricFormat.percent(0.1234, decimals: 1), "12.3%")
    }

    func testBytesFormat() {
        XCTAssertEqual(MetricFormat.bytes(1024), "1.0 KB")
        XCTAssertEqual(MetricFormat.bytes(1024 * 1024), "1.0 MB")
    }

    func testSparklineLength() {
        let line = MetricFormat.sparkline([0, 0.5, 1])
        XCTAssertEqual(line.count, 3)
    }

    // MARK: - Provider sanity checks (real hardware)

    func testCPUProviderProducesValueAfterTwoSamples() {
        let cpu = CPUProvider()
        _ = cpu.sample() // first sample is the reference
        // Create a short workload.
        var acc = 0.0
        for i in 0..<200_000 { acc += Double(i).squareRoot() }
        _ = acc
        let second = cpu.sample()
        XCTAssertNotNil(second)
        if let s = second {
            XCTAssertGreaterThanOrEqual(s.value, 0)
            XCTAssertLessThanOrEqual(s.value, 1)
            XCTAssertGreaterThan(s.detail["coreCount"] ?? 0, 0)
        }
    }

    func testMemoryProviderReadsPhysicalMemory() {
        let mem = MemoryProvider()
        let sample = mem.sample()
        XCTAssertNotNil(sample)
        if let s = sample {
            XCTAssertGreaterThan(s.detail["total"] ?? 0, 0)
            XCTAssertGreaterThanOrEqual(s.value, 0)
            XCTAssertLessThanOrEqual(s.value, 1)
        }
    }

    func testNetworkProviderProducesNonNegativeRates() {
        let net = NetworkProvider()
        _ = net.sample() // reference
        let second = net.sample()
        XCTAssertNotNil(second)
        if let s = second {
            XCTAssertGreaterThanOrEqual(s.detail["down"] ?? -1, 0)
            XCTAssertGreaterThanOrEqual(s.detail["up"] ?? -1, 0)
        }
    }

    func testDiskProviderReportsCapacity() {
        let disk = DiskProvider()
        let sample = disk.sample()
        XCTAssertNotNil(sample)
        if let s = sample {
            XCTAssertGreaterThan(s.detail["total"] ?? 0, 0)
            XCTAssertGreaterThanOrEqual(s.value, 0)
            XCTAssertLessThanOrEqual(s.value, 1)
        }
    }

    func testCompactRateFormat() {
        XCTAssertEqual(MetricFormat.compactRate(512), "512")
        XCTAssertEqual(MetricFormat.compactRate(2048), "2.0K")
    }
}
