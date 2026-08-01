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
            pausedMetricIDs: [.sensors, .fans]
        )
        XCTAssertEqual(policy.intervalMultiplier, 1)
        XCTAssertEqual(policy.heavyEveryNCycles, 1)
        XCTAssertEqual(policy.pausedMetricIDs, [.sensors, .fans])
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

    func testNetworkRateSurvivesCounterResets() {
        let net = NetworkProvider()
        let start = Date(timeIntervalSince1970: 1_000)

        XCTAssertNil(
            net.makeSample(down: 5_000, up: 1_000, now: start),
            "the reference pass must not fabricate a zero sample"
        )

        let rate = net.makeSample(down: 7_000, up: 1_500, now: start.addingTimeInterval(2))
        XCTAssertEqual(rate?.detail["down"], 1_000)
        XCTAssertEqual(rate?.detail["up"], 250)
        XCTAssertEqual(rate?.value, 1_250)

        // An interface disappearing (or a 32-bit fallback counter wrapping) lowers the
        // total; that must read as no traffic, not as a multi-gigabyte spike.
        let afterReset = net.makeSample(down: 10, up: 5, now: start.addingTimeInterval(4))
        XCTAssertEqual(afterReset?.detail["down"], 0)
        XCTAssertEqual(afterReset?.detail["up"], 0)
        XCTAssertEqual(afterReset?.detail["downTotal"], 10)

        // The next pass measures from the new baseline.
        let resumed = net.makeSample(down: 110, up: 5, now: start.addingTimeInterval(6))
        XCTAssertEqual(resumed?.detail["down"], 50)
    }

    func testNetworkTotalsUseSixtyFourBitCounters() {
        // The routing-table read reports the machine's lifetime byte counts, which are
        // routinely larger than the 32-bit range a long-running Mac would wrap.
        let net = NetworkProvider()
        _ = net.sample()
        guard let sample = net.sample() else { return XCTFail("no network sample") }
        let total = (sample.detail["downTotal"] ?? 0) + (sample.detail["upTotal"] ?? 0)
        XCTAssertGreaterThan(total, 0)
        XCTAssertLessThan(total, Double(UInt64.max))
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
        XCTAssertGreaterThanOrEqual(next?.detail["readRate"] ?? -1, 0)
        XCTAssertGreaterThanOrEqual(next?.detail["writeRate"] ?? -1, 0)
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

    func testMemoryTemperatureKeysDoNotConfuseTheIntelMainboardSensor() {
        XCTAssertTrue(SensorsProvider.isMemoryTemperatureKey("TM0P"))
        XCTAssertTrue(SensorsProvider.isMemoryTemperatureKey("Tm02"))
        XCTAssertTrue(SensorsProvider.isMemoryTemperatureKey("Tm2p"))
        XCTAssertFalse(SensorsProvider.isMemoryTemperatureKey("Tm0P"))
        XCTAssertFalse(SensorsProvider.isMemoryTemperatureKey("TC0P"))
    }

    func testFansProviderIsCoherentWhenPresent() {
        // Fanless machines legitimately report unavailable; only assert coherence.
        let provider = FansProvider()
        guard provider.isAvailable, let sample = provider.sample() else { return }
        XCTAssertTrue((0...1).contains(sample.value))
        XCTAssertGreaterThanOrEqual(Int(sample.detail["fanCount"] ?? 0), 1)
    }

    func testFansProviderSamplesDetectedFans() throws {
        let reader = MockSMCValueReader(values: [
            "FNum": 2,
            "F0Ac": 2_000,
            "F0Mx": 5_000,
            "F1Ac": 2_400,
            "F1Mx": 4_800
        ])
        let provider = FansProvider(smc: reader)

        XCTAssertTrue(provider.isAvailable)
        let sample = try XCTUnwrap(provider.sample())
        XCTAssertEqual(sample.unit, .fraction)
        XCTAssertEqual(sample.value, 0.5, accuracy: 0.001)
        XCTAssertEqual(sample.detail["fanCount"], 2)
        XCTAssertEqual(sample.detail["fan0Rpm"], 2_000)
        XCTAssertEqual(sample.detail["fan1Rpm"], 2_400)
        XCTAssertEqual(sample.detail["maxRpm"], 2_400)
    }

    func testFansProviderFallsBackToSpeedKeysWhenCountIsMissing() throws {
        let reader = MockSMCValueReader(values: [
            "F0Ac": 1_800,
            "F0Mx": 4_500
        ])
        let provider = FansProvider(smc: reader)

        XCTAssertTrue(provider.isAvailable)
        let sample = try XCTUnwrap(provider.sample())
        XCTAssertEqual(sample.detail["fanCount"], 1)
        XCTAssertEqual(sample.detail["fan0Rpm"], 1_800)
        XCTAssertEqual(sample.value, 0.4, accuracy: 0.001)
    }

    func testDiskThroughputSurvivesAVolumeDisappearing() {
        let disk = DiskProvider()
        let start = Date()

        // First reading is only a reference point.
        XCTAssertTrue(
            disk.throughput(read: 8_000, write: 4_000, now: start).isEmpty
        )

        let rates = disk.throughput(
            read: 10_000,
            write: 5_000,
            now: start.addingTimeInterval(2)
        )
        XCTAssertEqual(rates["readRate"], 1_000)
        XCTAssertEqual(rates["writeRate"], 500)

        // Unplugging an external disk takes its lifetime counters out of the sum, so
        // the totals go backwards. Unsigned subtraction would wrap that into ~10^19
        // bytes per second; no traffic is the honest answer.
        let afterEject = disk.throughput(
            read: 1_000,
            write: 500,
            now: start.addingTimeInterval(4)
        )
        XCTAssertEqual(afterEject["readRate"], 0)
        XCTAssertEqual(afterEject["writeRate"], 0)

        // The smaller totals become the new baseline, so counting resumes normally.
        let resumed = disk.throughput(
            read: 3_000,
            write: 1_500,
            now: start.addingTimeInterval(6)
        )
        XCTAssertEqual(resumed["readRate"], 1_000)
        XCTAssertEqual(resumed["writeRate"], 500)
    }

    func testFansProviderRejectsImplausibleSpeeds() {
        // A key decoded under the wrong SMC type yields a number, not an error. Such a
        // reading is not a fan, and must not reach the menu bar as one.
        let provider = FansProvider(
            smc: MockSMCValueReader(values: ["FNum": 1, "F0Ac": 4_000_000])
        )

        XCTAssertNil(provider.sample())
    }

    func testFansProviderKeepsFanlessMacsUnavailable() {
        let provider = FansProvider(
            smc: MockSMCValueReader(values: ["FNum": 0])
        )

        XCTAssertFalse(provider.isAvailable)
        XCTAssertNil(provider.sample())
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
        // Above the largest unit there is nothing left to scale by. Without a clamp the
        // mantissa grows without bound and the menu bar item outgrows its reserved
        // slot, so the ceiling is checked here rather than assumed unreachable.
        XCTAssertEqual(MetricFormat.menuRate(999_000_000_000_000_000), "999T")
        for exponent in 3...30 {
            let value = pow(10.0, Double(exponent))
            XCTAssertLessThanOrEqual(MetricFormat.menuRate(value).count, 4,
                                     "menuRate(1e\(exponent)) too wide")
            XCTAssertLessThanOrEqual(MetricFormat.menuRate(value * 5.5).count, 4,
                                     "menuRate(5.5e\(exponent)) too wide")
        }
    }
}

private final class MockSMCValueReader: SMCValueReading {
    private let values: [String: Double]

    init(values: [String: Double]) {
        self.values = values
    }

    func readValue(_ name: String) -> Double? {
        values[name]
    }
}

/// A heavy provider, which the runtime policy is allowed to slow down or pause.
/// The engine samples on its own queue while the test reads the counter, so the count is
/// lock-guarded rather than relying on the provider's single-queue contract.
private final class HeavyTestProvider: MetricProvider, @unchecked Sendable {
    let id = MetricID.sensors
    let cost = SamplingCost.heavy

    private let lock = NSLock()
    private var count = 0

    var sampleCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func sample() -> MetricSample? {
        lock.lock()
        count += 1
        lock.unlock()
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
