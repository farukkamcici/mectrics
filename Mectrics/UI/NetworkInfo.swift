import Foundation
import Darwin

/// Local network info read on demand (popover open) via `getifaddrs` — no network
/// requests, fully offline, in keeping with the zero-telemetry promise. Public IP is
/// deliberately NOT shown: it would require calling an external service.
enum NetworkInfo {
    /// The primary interface's name and IPv4 address (e.g. ("en0", "192.168.1.76")).
    static func primaryIPv4() -> (interface: String, address: String)? {
        var first: (String, String)?
        var ifaddrsPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrsPtr) == 0, let start = ifaddrsPtr else { return nil }
        defer { freeifaddrs(ifaddrsPtr) }

        for ptr in sequence(first: start, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
                  (ifa.ifa_flags & UInt32(IFF_UP)) != 0,
                  (ifa.ifa_flags & UInt32(IFF_LOOPBACK)) == 0
            else { continue }

            let name = String(cString: ifa.ifa_name)
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                              &host, socklen_t(host.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let address = String(cString: host)

            // Prefer the built-in Wi-Fi/Ethernet interfaces; fall back to anything up.
            if name == "en0" { return (name, address) }
            if first == nil { first = (name, address) }
        }
        return first
    }
}
