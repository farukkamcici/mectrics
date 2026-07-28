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
/// as unavailable (hidden in the menu bar). Device names will be added later via a
/// separate channel (the detail dictionary is Double-only).
public final class BluetoothProvider: MetricProvider, @unchecked Sendable {
    public let id: MetricID = .bluetooth
    public let cost: SamplingCost = .medium

    public init() {}

    public var isAvailable: Bool {
        !scanBatteryDevices().isEmpty
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
    private static var latestNames: [String] = []

    public func sample() -> MetricSample? {
        let devices = scanBatteryDevices()
        guard !devices.isEmpty else { return nil }

        Self.namesLock.lock()
        Self.latestNames = devices.map(\.name)
        Self.namesLock.unlock()

        let minPct = devices.map(\.percent).min() ?? 0
        var detail: [String: Double] = ["deviceCount": Double(devices.count)]
        for (i, device) in devices.enumerated() {
            detail["device\(i)"] = device.percent
        }
        return MetricSample(value: minPct / 100, unit: .fraction, detail: detail)
    }

    /// Recursively scans the IORegistry and collects entries that expose
    /// `BatteryPercent`, with their product names.
    private func scanBatteryDevices() -> [(name: String, percent: Double)] {
        var result: [(name: String, percent: Double)] = []
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

            let name = (dict["Product"] as? String)
                ?? (dict["DeviceName"] as? String)
                ?? ""

            // Single-cell devices (Magic Mouse/Keyboard, most headphones).
            if let pct = (dict["BatteryPercent"] as? NSNumber)?.doubleValue, pct > 0 {
                result.append((name: name, percent: pct))
            }
            // AirPods publish per-component keys instead of BatteryPercent.
            let componentKeys: [(String, String)] = [
                ("BatteryPercentLeft", "L"), ("BatteryPercentRight", "R"),
                ("BatteryPercentCase", "Case")
            ]
            for (key, suffix) in componentKeys {
                if let pct = (dict[key] as? NSNumber)?.doubleValue, pct > 0 {
                    let label = name.isEmpty ? suffix : "\(name) (\(suffix))"
                    result.append((name: label, percent: pct))
                }
            }
        }
        return result
    }
}
