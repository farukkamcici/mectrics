import Foundation
import Darwin

/// Reads physical memory usage via Mach `host_statistics64` (VM statistics).
///
/// `value` = used-memory fraction (0...1). A close approximation to Activity Monitor's
/// "Memory Used": used ≈ (active + wired + compressed). The detail dictionary carries all
/// components in bytes so the UI can show the real breakdown.
public final class MemoryProvider: MetricProvider, @unchecked Sendable {
    public let id: MetricID = .memory
    public let cost: SamplingCost = .light

    private let pageSize: Double
    private let totalMemory: Double

    public init() {
        var size: vm_size_t = 0
        host_page_size(mach_host_self(), &size)
        self.pageSize = Double(size)

        var mem: UInt64 = 0
        var len = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &mem, &len, nil, 0)
        self.totalMemory = Double(mem)
    }

    public func sample() -> MetricSample? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )

        let result = withUnsafeMutablePointer(to: &stats) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let active     = Double(stats.active_count) * pageSize
        let inactive   = Double(stats.inactive_count) * pageSize
        let wired      = Double(stats.wire_count) * pageSize
        let compressed = Double(stats.compressor_page_count) * pageSize
        let free       = Double(stats.free_count) * pageSize
        let purgeable  = Double(stats.purgeable_count) * pageSize

        // Used-memory approximation (close to Activity Monitor).
        let used = active + wired + compressed
        let usage = totalMemory > 0 ? min(max(used / totalMemory, 0), 1) : 0

        let detail: [String: Double] = [
            "total": totalMemory,
            "used": used,
            "active": active,
            "inactive": inactive,
            "wired": wired,
            "compressed": compressed,
            "free": free,
            "purgeable": purgeable
        ]

        return MetricSample(value: usage, unit: .fraction, detail: detail)
    }
}
