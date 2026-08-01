import Foundation
import IOKit

/// Reports the main disk (`/`) usage and read/write throughput.
///
/// `value` = used-space fraction (0...1). Detail: total, free, used (bytes),
/// readRate, writeRate (bytes/s). Capacity comes from `statfs`; throughput from the
/// delta of IOKit `IOBlockStorageDriver` statistics.
///
/// Capacity is split across two cadences. `statfs` is a single syscall and runs on
/// every sample, so used and free stay live. The purgeable figure needs
/// `volumeAvailableCapacityForImportantUsage`, which routes through the system's cache
/// deletion machinery and costs roughly eleven milliseconds of CPU per call — three
/// orders of magnitude more than everything else this provider does. Reclaimable space
/// moves on the scale of minutes, so it is refreshed on its own slow interval and
/// carried forward in between.
public final class DiskProvider: MetricProvider, @unchecked Sendable {
    public let id: MetricID = .disk
    public let cost: SamplingCost = .medium

    /// How often the expensive purgeable-space query is allowed to run.
    private static let purgeableRefreshInterval: TimeInterval = 60

    private var prevRead: UInt64 = 0
    private var prevWrite: UInt64 = 0
    private var prevTime: Date?
    private var purgeable: Double = 0
    private var purgeableReadAt: Date?

    public init() {}

    public func sample() -> MetricSample? {
        let now = Date()
        guard let capacity = readCapacity() else { return nil }
        let purgeable = refreshedPurgeable(
            total: capacity.total,
            strictFree: capacity.strictFree,
            now: now
        )

        // Free space is reported the way the system does when it decides whether a
        // download fits: strictly-free plus whatever it could reclaim.
        let free = min(capacity.strictFree + purgeable, capacity.total)
        let used = max(capacity.total - free, 0)
        let usage = min(used / capacity.total, 1)

        let (read, write) = readBlockStats()
        var detail: [String: Double] = [
            "total": capacity.total,
            "free": free,
            "used": used,
            "purgeable": purgeable
        ]
        detail.merge(throughput(read: read, write: write, now: now)) { _, new in new }

        return MetricSample(
            value: usage,
            unit: .fraction,
            detail: detail
        )
    }

    /// Turns two cumulative byte counters into rates. Separated from the IOKit read so
    /// the first-sample and counter-reset behavior can be tested deterministically.
    ///
    /// The totals are summed across every `IOBlockStorageDriver` on the machine, so
    /// unplugging an external disk takes its lifetime counters out of the sum and the
    /// next reading is *smaller* than the last. Unsigned subtraction would wrap that
    /// into roughly 10^19 bytes per second. A shrinking total means a volume went away,
    /// not that the disk moved exabytes in a second, so report no throughput for that
    /// direction — the same reasoning `NetworkProvider` applies to a disappearing
    /// interface.
    func throughput(read: UInt64, write: UInt64, now: Date) -> [String: Double] {
        defer {
            prevRead = read
            prevWrite = write
            prevTime = now
        }

        // First sample: store the reference, don't produce a rate.
        guard let last = prevTime else { return [:] }
        let dt = now.timeIntervalSince(last)
        guard dt > 0 else { return [:] }

        return [
            "readRate": read >= prevRead ? Double(read - prevRead) / dt : 0,
            "writeRate": write >= prevWrite ? Double(write - prevWrite) / dt : 0
        ]
    }

    /// Total and strictly-free bytes on `/` from one `statfs` syscall. `f_bavail` is
    /// the space available to an unprivileged process — the same quantity
    /// `volumeAvailableCapacity` reports, to within a block.
    private func readCapacity() -> (total: Double, strictFree: Double)? {
        var stats = statfs()
        guard statfs("/", &stats) == 0 else { return nil }
        let blockSize = Double(stats.f_bsize)
        let total = Double(stats.f_blocks) * blockSize
        let strictFree = Double(stats.f_bavail) * blockSize
        guard total > 0 else { return nil }
        return (total, strictFree)
    }

    /// Space the system could reclaim (caches, snapshots): the difference between the
    /// "important usage" capacity and the strictly-free figure. Refreshed at most once
    /// per `purgeableRefreshInterval`, and carried forward in between.
    private func refreshedPurgeable(
        total: Double,
        strictFree: Double,
        now: Date
    ) -> Double {
        if let readAt = purgeableReadAt,
           now.timeIntervalSince(readAt) < Self.purgeableRefreshInterval {
            // A carried-forward figure must still fit inside the disk it describes.
            return min(purgeable, max(total - strictFree, 0))
        }
        purgeableReadAt = now
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey
        ]), let important = values.volumeAvailableCapacityForImportantUsage
        else {
            purgeable = 0
            return 0
        }
        purgeable = max(Double(important) - strictFree, 0)
        return purgeable
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
            // Copying the one property that is needed avoids materializing the
            // driver's entire property dictionary on every sample.
            guard let stats = IORegistryEntryCreateCFProperty(
                service,
                "Statistics" as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue() as? [String: Any]
            else { continue }

            if let r = (stats["Bytes (Read)"] as? NSNumber)?.uint64Value { read &+= r }
            if let w = (stats["Bytes (Write)"] as? NSNumber)?.uint64Value { write &+= w }
        }
        return (read, write)
    }
}
