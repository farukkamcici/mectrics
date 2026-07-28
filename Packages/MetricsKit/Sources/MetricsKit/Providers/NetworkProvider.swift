import Foundation
import Darwin

/// Computes network throughput from interface counters via `getifaddrs`.
///
/// The cumulative ibytes/obytes counters differenced between two consecutive samples,
/// divided by elapsed time, give the rate. All link-layer (AF_LINK) interfaces except
/// loopback (`lo*`) are summed. `value` = total (down + up) bytes/s.
/// Detail: down, up, downTotal, upTotal.
///
/// Note: `if_data` counters are 32-bit and wrap at ~4 GB. At 1–2 s sampling this is not a
/// practical problem. Can be hardened later with NET_RT_IFLIST2 (64-bit).
public final class NetworkProvider: MetricProvider, @unchecked Sendable {
    public let id: MetricID = .network
    public let cost: SamplingCost = .medium

    private var prevDown: UInt64 = 0
    private var prevUp: UInt64 = 0
    private var prevTime: Date?

    public init() {}

    public func sample() -> MetricSample? {
        let (down, up) = readTotals()
        let now = Date()

        // First sample: store reference, don't produce a rate.
        guard let last = prevTime else {
            prevDown = down; prevUp = up; prevTime = now
            return nil
        }

        let dt = now.timeIntervalSince(last)
        guard dt > 0 else {
            prevDown = down; prevUp = up; prevTime = now
            return nil
        }
        let downRate = Double(down &- prevDown) / dt
        let upRate = Double(up &- prevUp) / dt

        prevDown = down; prevUp = up; prevTime = now

        return MetricSample(
            value: downRate + upRate,
            unit: .bytesPerSecond,
            detail: ["down": downRate, "up": upRate,
                     "downTotal": Double(down), "upTotal": Double(up)]
        )
    }

    private func readTotals() -> (UInt64, UInt64) {
        var down: UInt64 = 0
        var up: UInt64 = 0
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else { return (0, 0) }
        defer { freeifaddrs(ifaddrPtr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = ptr {
            let ifa = cur.pointee
            if let addr = ifa.ifa_addr,
               Int32(addr.pointee.sa_family) == AF_LINK {
                let name = String(cString: ifa.ifa_name)
                if !name.hasPrefix("lo"), let data = ifa.ifa_data {
                    let stats = data.assumingMemoryBound(to: if_data.self).pointee
                    down &+= UInt64(stats.ifi_ibytes)
                    up &+= UInt64(stats.ifi_obytes)
                }
            }
            ptr = ifa.ifa_next
        }
        return (down, up)
    }
}
