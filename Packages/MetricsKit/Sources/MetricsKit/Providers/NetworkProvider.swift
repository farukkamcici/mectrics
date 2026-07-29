import Foundation
import Darwin

/// Computes network throughput from the kernel's 64-bit interface counters.
///
/// The cumulative ibytes/obytes counters differenced between two consecutive samples,
/// divided by elapsed time, give the rate. All non-loopback interfaces are summed.
/// `value` = total (down + up) bytes/s. Detail: down, up, downTotal, upTotal.
///
/// The counters come from `sysctl(NET_RT_IFLIST2)`, whose `if_data64` payload is 64-bit
/// and therefore survives long uptimes. The `getifaddrs` path is kept as a fallback for
/// the rare case where the routing sysctl is unavailable; its `if_data` counters are
/// 32-bit and wrap at ~4 GB, which a decreasing total absorbs as a zero rate.
public final class NetworkProvider: MetricProvider, @unchecked Sendable {
    public let id: MetricID = .network
    public let cost: SamplingCost = .medium

    private var prevDown: UInt64 = 0
    private var prevUp: UInt64 = 0
    private var prevTime: Date?

    public init() {}

    public func sample() -> MetricSample? {
        guard let totals = Self.readTotals() else { return nil }
        return makeSample(down: totals.down, up: totals.up, now: Date())
    }

    /// Turns two cumulative readings into a rate. Separated from the system read so the
    /// counter-reset and first-sample behavior can be tested deterministically.
    func makeSample(down: UInt64, up: UInt64, now: Date) -> MetricSample? {
        defer {
            prevDown = down
            prevUp = up
            prevTime = now
        }

        // First sample: store the reference, don't produce a rate.
        guard let last = prevTime else { return nil }

        let dt = now.timeIntervalSince(last)
        guard dt > 0 else { return nil }

        // Counters only grow while an interface exists. A smaller reading means an
        // interface went away or a 32-bit fallback counter wrapped, so report no traffic
        // for that direction instead of a phantom spike.
        let downRate = down >= prevDown ? Double(down - prevDown) / dt : 0
        let upRate = up >= prevUp ? Double(up - prevUp) / dt : 0

        return MetricSample(
            value: downRate + upRate,
            unit: .bytesPerSecond,
            detail: ["down": downRate, "up": upRate,
                     "downTotal": Double(down), "upTotal": Double(up)]
        )
    }

    private static func readTotals() -> (down: UInt64, up: UInt64)? {
        routingTableTotals() ?? interfaceAddressTotals()
    }

    /// 64-bit counters from the routing table (`NET_RT_IFLIST2`).
    private static func routingTableTotals() -> (down: UInt64, up: UInt64)? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var size = 0
        guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0, size > 0 else {
            return nil
        }

        var buffer = [UInt8](repeating: 0, count: size)
        let read = buffer.withUnsafeMutableBytes { raw -> Bool in
            sysctl(&mib, u_int(mib.count), raw.baseAddress, &size, nil, 0) == 0
        }
        guard read, size > 0 else { return nil }

        var down: UInt64 = 0
        var up: UInt64 = 0
        let headerSize = MemoryLayout<if_msghdr>.size

        buffer.withUnsafeBytes { raw in
            var offset = 0
            while offset + headerSize <= size {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                let length = Int(header.ifm_msglen)
                guard length > 0, offset + length <= size else { break }
                defer { offset += length }

                guard Int32(header.ifm_type) == RTM_IFINFO2,
                      length >= MemoryLayout<if_msghdr2>.size
                else { continue }

                let message = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                guard message.ifm_flags & IFF_LOOPBACK == 0 else { continue }

                down &+= message.ifm_data.ifi_ibytes
                up &+= message.ifm_data.ifi_obytes
            }
        }
        return (down, up)
    }

    /// 32-bit fallback for systems where the routing sysctl returns nothing.
    private static func interfaceAddressTotals() -> (down: UInt64, up: UInt64)? {
        var down: UInt64 = 0
        var up: UInt64 = 0
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else { return nil }
        defer { freeifaddrs(ifaddrPtr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = ptr {
            let ifa = cur.pointee
            if let addr = ifa.ifa_addr,
               Int32(addr.pointee.sa_family) == AF_LINK,
               ifa.ifa_flags & UInt32(IFF_LOOPBACK) == 0,
               let data = ifa.ifa_data {
                let stats = data.assumingMemoryBound(to: if_data.self).pointee
                down &+= UInt64(stats.ifi_ibytes)
                up &+= UInt64(stats.ifi_obytes)
            }
            ptr = ifa.ifa_next
        }
        return (down, up)
    }
}
