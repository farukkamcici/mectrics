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
        !scanBatteryPercents().isEmpty
    }

    public func sample() -> MetricSample? {
        let percents = scanBatteryPercents()
        guard !percents.isEmpty else { return nil }

        let minPct = percents.min() ?? 0
        var detail: [String: Double] = ["deviceCount": Double(percents.count)]
        for (i, pct) in percents.enumerated() {
            detail["device\(i)"] = pct
        }
        return MetricSample(value: minPct / 100, unit: .fraction, detail: detail)
    }

    /// Recursively scans the IORegistry and collects the percentages of entries that
    /// expose `BatteryPercent`.
    private func scanBatteryPercents() -> [Double] {
        var result: [Double] = []
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

            if let pct = (dict["BatteryPercent"] as? NSNumber)?.doubleValue, pct > 0 {
                result.append(pct)
            }
        }
        return result
    }
}
