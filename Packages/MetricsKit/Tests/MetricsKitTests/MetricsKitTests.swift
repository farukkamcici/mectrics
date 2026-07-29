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

    func testStoreSupportsConcurrentReadsAndWrites() {
        let store = MetricStore(capacity: 64)
        DispatchQueue.concurrentPerform(iterations: 1_000) { index in
            store.append(MetricSample(value: Double(index)), for: .cpu)
            _ = store.latest(.cpu)
            _ = store.history(.cpu, count: 16)
        }
        XCTAssertEqual(store.history(.cpu).count, 64)
    }

    func testSharedSnapshotRoundTrip() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let snapshot = SharedMetricSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_000),
            orderedMetricIDs: [.cpu, .memory],
            samples: [
                .cpu: MetricSample(
                    timestamp: Date(timeIntervalSince1970: 999),
                    value: 0.42
                )
            ],
            histories: [.cpu: [0.2, 0.3, 0.42]],
            states: [.cpu: .live, .memory: .collecting]
        )
        let store = SharedMetricSnapshotStore(fileURL: fileURL)
        try store.write(snapshot)

        XCTAssertEqual(try store.read(), snapshot)
    }

    func testSharedSnapshotDecodesLegacyPayloadWithoutStates() throws {
        let json = """
        {
          "generatedAt": 1000,
          "orderedMetricIDs": ["cpu"],
          "samples": [],
          "histories": []
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let snapshot = try decoder.decode(
            SharedMetricSnapshot.self,
            from: Data(json.utf8)
        )
        XCTAssertNil(snapshot.states)
    }

    func testMetricDataStateResolution() {
        let now = Date(timeIntervalSince1970: 1_000)
        let fresh = MetricSample(timestamp: now.addingTimeInterval(-2), value: 0.42)
        let old = MetricSample(timestamp: now.addingTimeInterval(-30), value: 0.42)

        XCTAssertEqual(
            MetricDataState.resolve(
                isAvailable: true,
                isEnabled: true,
                sample: nil,
                now: now
            ),
            .collecting
        )
        XCTAssertEqual(
            MetricDataState.resolve(
                isAvailable: true,
                isEnabled: true,
                sample: fresh,
                now: now
            ),
            .live
        )
        XCTAssertEqual(
            MetricDataState.resolve(
                isAvailable: true,
                isEnabled: true,
                sample: old,
                now: now
            ),
            .stale
        )
        XCTAssertEqual(
            MetricDataState.resolve(
                isAvailable: true,
                isEnabled: true,
                sample: fresh,
                consecutiveFailures: 3,
                now: now
            ),
            .error
        )
        XCTAssertEqual(
            MetricDataState.resolve(
                isAvailable: true,
                isEnabled: true,
                sample: fresh,
                requiresPermission: true,
                now: now
            ),
            .permissionRequired
        )
        XCTAssertEqual(
            MetricDataState.resolve(
                isAvailable: true,
                isEnabled: false,
                sample: fresh,
                now: now
            ),
            .disabled
        )
        XCTAssertEqual(
            MetricDataState.resolve(
                isAvailable: false,
                isEnabled: true,
                sample: fresh,
                now: now
            ),
            .unavailable
        )
    }

    func testEnginePublishesFirstLiveMetricWithinTwoSeconds() {
        let expectation = expectation(description: "first live metric")
        let start = Date()
        let engine = MetricsEngine(
            policy: SamplingPolicy(
                onACInterval: 10,
                onBatteryInterval: 10,
                heavyEveryNCycles: 1
            )
        )
        engine.register([ImmediateTestProvider()])
        engine.setActiveMetrics([.cpu])
        engine.onCycleReport = { report in
            if report.samples[.cpu] != nil {
                expectation.fulfill()
            }
        }
        engine.start()
        wait(for: [expectation], timeout: 2)
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
        engine.stop()
    }

    func testEngineReportsFailedAttemptsWithoutFabricatingSamples() {
        let expectation = expectation(description: "failed attempt")
        let engine = MetricsEngine(
            policy: SamplingPolicy(
                onACInterval: 10,
                onBatteryInterval: 10,
                heavyEveryNCycles: 1
            )
        )
        engine.register([FailingTestProvider()])
        engine.setActiveMetrics([.cpu])
        engine.onCycleReport = { report in
            XCTAssertTrue(report.samples.isEmpty)
            XCTAssertEqual(report.failedMetricIDs, [.cpu])
            expectation.fulfill()
        }
        engine.start()
        wait(for: [expectation], timeout: 2)
        engine.stop()
    }

    func testExplicitRefreshReadsProvidersTheRuntimePolicyHeldBack() {
        let heavy = HeavyTestProvider()
        let engine = MetricsEngine()
        engine.register([heavy])
        engine.updateRuntimePolicy(
            SamplingRuntimePolicy(
                intervalMultiplier: 3,
                heavyEveryNCycles: 8,
                pausedMetricIDs: [.sensors]
            )
        )

        let paused = expectation(description: "paused refresh")
        engine.requestRefresh()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { paused.fulfill() }
        wait(for: [paused], timeout: 2)
        XCTAssertEqual(
            heavy.sampleCount,
            0,
            "A background refresh must respect the energy policy"
        )

        let forced = expectation(description: "explicit refresh")
        engine.requestRefresh(includingHeavy: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { forced.fulfill() }
        wait(for: [forced], timeout: 2)
        XCTAssertEqual(
            heavy.sampleCount,
            1,
            "An explicit refresh must read what the policy paused"
        )
    }

    func testRuntimeSamplingPolicyClampsUnsafeValues() {
        let policy = SamplingRuntimePolicy(
            intervalMultiplier: 0,
            heavyEveryNCycles: 0,
            pausedMetricIDs: [.sensors, .bluetooth]
        )
        XCTAssertEqual(policy.intervalMultiplier, 1)
        XCTAssertEqual(policy.heavyEveryNCycles, 1)
        XCTAssertEqual(policy.pausedMetricIDs, [.sensors, .bluetooth])
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
        XCTAssertNil(cpu.sample(), "the reference pass must not fabricate a zero sample")
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
        XCTAssertNil(net.sample(), "the reference pass must not fabricate a zero sample")
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
            XCTAssertNil(s.detail["readRate"])
            XCTAssertNil(s.detail["writeRate"])
        }
        let next = disk.sample()
        XCTAssertNotNil(next?.detail["readRate"])
        XCTAssertNotNil(next?.detail["writeRate"])
    }

    func testBatteryServiceRecommendationUsesOnlySystemHealthValues() {
        XCTAssertEqual(
            BatteryProvider.serviceRecommendation(
                health: "Good",
                condition: nil
            ),
            false
        )
        XCTAssertEqual(
            BatteryProvider.serviceRecommendation(
                health: "Fair",
                condition: nil
            ),
            false
        )
        XCTAssertEqual(
            BatteryProvider.serviceRecommendation(
                health: "Poor",
                condition: nil
            ),
            true
        )
        XCTAssertEqual(
            BatteryProvider.serviceRecommendation(
                health: "Good",
                condition: "Check Battery"
            ),
            true
        )
        XCTAssertNil(
            BatteryProvider.serviceRecommendation(
                health: nil,
                condition: nil
            )
        )
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

/// A heavy provider, which the runtime policy is allowed to slow down or pause.
private final class HeavyTestProvider: MetricProvider {
    let id = MetricID.sensors
    let cost = SamplingCost.heavy
    private(set) var sampleCount = 0

    func sample() -> MetricSample? {
        sampleCount += 1
        return MetricSample(value: 42, unit: .celsius)
    }
}

private final class ImmediateTestProvider: MetricProvider {
    let id = MetricID.cpu
    func sample() -> MetricSample? {
        MetricSample(value: 0.5)
    }
}

private final class FailingTestProvider: MetricProvider {
    let id = MetricID.cpu
    func sample() -> MetricSample? {
        nil
    }
}
