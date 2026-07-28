import Foundation
import Darwin

/// Ağ verimini (throughput) `getifaddrs` ile arayüz sayaçlarından hesaplar.
///
/// Kümülatif ibytes/obytes sayaçlarının ardışık iki örnek farkı / geçen süre = hız.
/// Loopback (`lo*`) hariç tüm bağlantı katmanı (AF_LINK) arayüzleri toplanır.
/// `value` = toplam (indirme + yükleme) bytes/s. Ayrıntı: down, up, downTotal, upTotal.
///
/// Not: `if_data` sayaçları 32-bit; ~4 GB'de sarar. 1–2 sn örneklemede pratikte sorun
/// olmaz. İleride NET_RT_IFLIST2 (64-bit) ile güçlendirilebilir.
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

        // İlk örnek: referansı sakla, hız üretme.
        guard let last = prevTime else {
            prevDown = down; prevUp = up; prevTime = now
            return MetricSample(value: 0, unit: .bytesPerSecond,
                                detail: ["down": 0, "up": 0,
                                         "downTotal": Double(down), "upTotal": Double(up)])
        }

        let dt = now.timeIntervalSince(last)
        let downRate = dt > 0 ? Double(down &- prevDown) / dt : 0
        let upRate = dt > 0 ? Double(up &- prevUp) / dt : 0

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
