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

    func testGPUProviderSampleIsNormalized() {
        // Hardware-dependent: only assert when an accelerator publishes statistics
        // (true on every Apple Silicon Mac; may be false in a VM/CI box).
        let provider = GPUProvider()
        guard provider.isAvailable else { return }
        let sample = provider.sample()
        XCTAssertNotNil(sample)
        if let sample {
            XCTAssertGreaterThanOrEqual(sample.value, 0)
            XCTAssertLessThanOrEqual(sample.value, 1)
            XCTAssertGreaterThanOrEqual(Int(sample.detail["gpuCount"] ?? 0), 1)
        }
    }

    func testSensorsProviderReportsPlausibleTemperatures() {
        // Hardware-dependent: SMC may be absent in a VM. On real hardware the hottest
        // sensor must stay in the plausible range the provider itself filters by.
        let provider = SensorsProvider()
        guard provider.isAvailable else { return }
        let sample = provider.sample()
        XCTAssertNotNil(sample)
        if let sample {
            XCTAssertEqual(sample.unit, .celsius)
            XCTAssertTrue((1...125).contains(sample.value), "implausible temp \(sample.value)")
            XCTAssertGreaterThanOrEqual(Int(sample.detail["sensorCount"] ?? 0), 1)
        }
    }

    func testFansProviderIsCoherentWhenPresent() {
        // Fanless machines legitimately report unavailable; only assert coherence.
        let provider = FansProvider()
        guard provider.isAvailable, let sample = provider.sample() else { return }
        XCTAssertTrue((0...1).contains(sample.value))
        XCTAssertGreaterThanOrEqual(Int(sample.detail["fanCount"] ?? 0), 1)
    }

    func testMenuRateIsCompactAndBounded() {
        // Sub-KB/s collapses to "0".
        XCTAssertEqual(MetricFormat.menuRate(0), "0")
        XCTAssertEqual(MetricFormat.menuRate(500), "0")
        // Small values keep one decimal; larger values drop it.
        XCTAssertEqual(MetricFormat.menuRate(1200), "1.2K")
        XCTAssertEqual(MetricFormat.menuRate(35_000), "35K")
        XCTAssertEqual(MetricFormat.menuRate(999_000), "999K")
        XCTAssertEqual(MetricFormat.menuRate(1_200_000), "1.2M")
        XCTAssertEqual(MetricFormat.menuRate(120_000_000), "120M")
        // Every output is at most 4 glyphs so the reserved slot stays narrow.
        for v in stride(from: 0.0, through: 5_000_000_000, by: 137_113) {
            XCTAssertLessThanOrEqual(MetricFormat.menuRate(v).count, 4,
                                     "menuRate(\(v)) too wide")
        }
    }
}
