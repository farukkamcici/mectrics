import Foundation
import IOKit

/// Reads the battery levels of connected Bluetooth devices from the IORegistry
/// (best-effort).
///
/// Many devices (Magic Mouse/Keyboard, some headphones) publish a `BatteryPercent`
/// property in the IORegistry. `value` = lowest device battery (0...1) — a "most critical
/// device" indicator. Detail: deviceCount and device0..N battery percentages.
///
/// Note: battery reporting varies by device; if no device is found the module is treated
/// as unavailable (hidden in the menu bar). The detail dictionary is Double-only, so
/// device names travel through `latestDeviceNames()`. A device that publishes no usable
/// name yields an empty string there and is labeled by the app.
public final class BluetoothProvider: MetricProvider, @unchecked Sendable {
    public let id: MetricID = .bluetooth
    public let cost: SamplingCost = .medium

    public init() {}

    public var isAvailable: Bool {
        !Self.scanBatteryDevices().isEmpty
    }

    /// Device names from the latest scan, index-aligned with `device<i>` detail keys.
    /// The detail dictionary is Double-only, so names travel via this side channel
    /// (written on the sampling queue, read by the UI on main — guarded by a lock).
    public static func latestDeviceNames() -> [String] {
        namesLock.lock()
        defer { namesLock.unlock() }
        return latestNames
    }

    private static let namesLock = NSLock()
    private nonisolated(unsafe) static var latestNames: [String] = []

    private static func publish(names: [String]) {
        namesLock.lock()
        latestNames = names
        namesLock.unlock()
    }

    public func sample() -> MetricSample? {
        let devices = Self.scanBatteryDevices()
        guard !devices.isEmpty else {
            // Never leave the previous scan's names behind: a later sample with fewer
            // devices would pair a name with the wrong battery level.
            Self.publish(names: [])
            return nil
        }

        Self.publish(names: devices.map(\.name))

        let minPct = devices.map(\.percent).min() ?? 0
        var detail: [String: Double] = ["deviceCount": Double(devices.count)]
        for (i, device) in devices.enumerated() {
            detail["device\(i)"] = device.percent
        }
        return MetricSample(value: minPct / 100, unit: .fraction, detail: detail)
    }

    /// Recursively scans the IORegistry and collects entries that expose a battery
    /// percentage, with their product names.
    private static func scanBatteryDevices() -> [(name: String, percent: Double)] {
        var result: [(name: String, percent: Double)] = []
        var seen: Set<String> = []
        var iterator: io_iterator_t = 0
        guard IORegistryCreateIterator(
            kIOMainPortDefault,
            kIOServicePlane,
            IOOptionBits(kIORegistryIterateRecursively),
            &iterator
        ) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            defer {
                IOObjectRelease(entry)
                entry = IOIteratorNext(iterator)
            }
            var props: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0)
                    == KERN_SUCCESS,
                  let dict = props?.takeRetainedValue() as? [String: Any]
            else { continue }

            let name = productName(from: dict, entry: entry)

            /// The recursive scan can reach one physical device through more than one
            /// registry node; keep the first reading of a named device only.
            func append(_ label: String, _ percent: Double) {
                guard (1...100).contains(percent) else { return }
                if !label.isEmpty {
                    guard seen.insert("\(label.lowercased())#\(Int(percent))").inserted
                    else { return }
                }
                result.append((name: label, percent: percent))
            }

            // Single-cell devices (Magic Mouse/Keyboard, most headphones).
            if let pct = batteryPercent(dict["BatteryPercent"]) {
                append(name, pct)
            }
            // AirPods publish per-component keys instead of BatteryPercent.
            let componentKeys: [(String, String)] = [
                ("BatteryPercentLeft", "L"), ("BatteryPercentRight", "R"),
                ("BatteryPercentCase", "Case")
            ]
            for (key, suffix) in componentKeys {
                if let pct = batteryPercent(dict[key]) {
                    append(name.isEmpty ? suffix : "\(name) (\(suffix))", pct)
                }
            }
        }
        return result
    }

    /// Accepts the numeric and string shapes devices use for a battery percentage.
    private static func batteryPercent(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let text = value as? String { return Double(text) }
        return nil
    }

    /// Devices disagree about which key carries a human-readable name; fall back to the
    /// registry entry name and finally to an empty string the app labels itself.
    private static func productName(from dict: [String: Any], entry: io_object_t) -> String {
        let keys = ["Product", "DeviceName", "ProductName", "BD_NAME", "Bluetooth Product Name"]
        let padding = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\0"))
        for key in keys {
            if let name = (dict[key] as? String)?.trimmingCharacters(in: padding),
               !name.isEmpty {
                return name
            }
            if let data = dict[key] as? Data,
               let name = String(data: data, encoding: .utf8)?.trimmingCharacters(in: padding),
               !name.isEmpty {
                return name
            }
        }

        var buffer = [CChar](repeating: 0, count: MemoryLayout<io_name_t>.size)
        guard IORegistryEntryGetName(entry, &buffer) == KERN_SUCCESS else { return "" }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        let name = String(decoding: bytes, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Registry class names such as "AppleHIDDevice" are noise, not device names.
        return name.hasPrefix("Apple") || name.hasPrefix("IO") ? "" : name
    }
}
