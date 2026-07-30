import Foundation
import IOKit

/// Reads GPU utilization from the accelerator driver's `PerformanceStatistics`
/// dictionary in the IORegistry (`IOAccelerator` — `AGXAccelerator` on Apple Silicon,
/// `IntelAccelerator`/AMD on Intel Macs).
///
/// `value` = utilization 0...1 of the busiest GPU. Detail: `gpuCount`, and
/// `inUseMemory` (bytes) when the driver publishes it. No public API exposes GPU
/// utilization; this registry path is what open-source monitors (Stats, iStats)
/// use — treated as best-effort and hidden when nothing is published.
public final class GPUProvider: MetricProvider, @unchecked Sendable {
    public let id: MetricID = .gpu
    public let cost: SamplingCost = .heavy

    /// Utilization keys published by different driver generations, in priority order.
    private static let utilizationKeys = [
        "Device Utilization %",
        "GPU Activity(%)"
    ]

    public init() {}

    public var isAvailable: Bool { read() != nil }

    public func sample() -> MetricSample? {
        guard let reading = read() else { return nil }
        var detail: [String: Double] = ["gpuCount": Double(reading.gpuCount)]
        if let memory = reading.inUseMemory { detail["inUseMemory"] = memory }
        return MetricSample(value: reading.utilization / 100, unit: .fraction, detail: detail)
    }

    private struct Reading {
        var utilization: Double
        var gpuCount: Int
        var inUseMemory: Double?
    }

    private func read() -> Reading? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOAccelerator"),
            &iterator
        ) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        var reading: Reading?
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            defer {
                IOObjectRelease(entry)
                entry = IOIteratorNext(iterator)
            }
            // Accelerators publish a large property dictionary; copying only the
            // statistics sub-dictionary is roughly a hundred times cheaper than
            // materializing all of it to read one key.
            guard let stats = IORegistryEntryCreateCFProperty(
                entry,
                "PerformanceStatistics" as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue() as? [String: Any]
            else { continue }

            guard let utilization = Self.utilizationKeys
                .compactMap({ (stats[$0] as? NSNumber)?.doubleValue })
                .first
            else { continue }

            var current = reading ?? Reading(utilization: 0, gpuCount: 0, inUseMemory: nil)
            current.gpuCount += 1
            // Multi-GPU machines: report the busiest one.
            current.utilization = max(current.utilization, min(max(utilization, 0), 100))
            if let memory = (stats["In use system memory"] as? NSNumber)?.doubleValue {
                current.inUseMemory = (current.inUseMemory ?? 0) + memory
            }
            reading = current
        }
        return reading
    }
}
