import Foundation
import IOKit

/// Reports the main disk (`/`) usage and read/write throughput.
///
/// `value` = used-space fraction (0...1). Detail: total, free, used (bytes),
/// readRate, writeRate (bytes/s). Capacity comes from `URL` resource values; throughput
/// from the delta of IOKit `IOBlockStorageDriver` statistics.
public final class DiskProvider: MetricProvider, @unchecked Sendable {
    public let id: MetricID = .disk
    public let cost: SamplingCost = .medium

    private var prevRead: UInt64 = 0
    private var prevWrite: UInt64 = 0
    private var prevTime: Date?

    public init() {}

    public func sample() -> MetricSample? {
        // Capacity
        let url = URL(fileURLWithPath: "/")
        var total: Double = 0
        var free: Double = 0
        var purgeable: Double = 0
        if let vals = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]) {
            total = Double(vals.volumeTotalCapacity ?? 0)
            free = Double(vals.volumeAvailableCapacityForImportantUsage ?? 0)
            // "Important usage" capacity includes space the system can reclaim
            // (caches, snapshots); the strictly-free difference is purgeable.
            let strictFree = Double(vals.volumeAvailableCapacity ?? 0)
            purgeable = max(free - strictFree, 0)
        }
        let used = max(total - free, 0)
        let usage = total > 0 ? min(used / total, 1) : 0

        // Throughput
        let (read, write) = readBlockStats()
        let now = Date()
        var readRate: Double = 0
        var writeRate: Double = 0
        if let last = prevTime {
            let dt = now.timeIntervalSince(last)
            if dt > 0 {
                readRate = Double(read &- prevRead) / dt
                writeRate = Double(write &- prevWrite) / dt
            }
        }
        prevRead = read; prevWrite = write; prevTime = now

        return MetricSample(
            value: usage,
            unit: .fraction,
            detail: ["total": total, "free": free, "used": used, "purgeable": purgeable,
                     "readRate": readRate, "writeRate": writeRate]
        )
    }

    private func readBlockStats() -> (UInt64, UInt64) {
        var read: UInt64 = 0
        var write: UInt64 = 0
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOBlockStorageDriver"),
            &iterator
        ) == KERN_SUCCESS else { return (0, 0) }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            var props: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0)
                    == KERN_SUCCESS,
                  let dict = props?.takeRetainedValue() as? [String: Any],
                  let stats = dict["Statistics"] as? [String: Any]
            else { continue }

            if let r = (stats["Bytes (Read)"] as? NSNumber)?.uint64Value { read &+= r }
            if let w = (stats["Bytes (Write)"] as? NSNumber)?.uint64Value { write &+= w }
        }
        return (read, write)
    }
}
