import Foundation
import IOKit.ps
import IOKit

/// Reads battery state from the IOKit Power Sources API; queries the IORegistry
/// `AppleSmartBattery` entry for health/cycle info.
///
/// `value` = charge fraction (0...1). Detail: charging (1/0), timeToEmpty/Full (min),
/// cycleCount, healthPercent, temperature (°C), amperage/voltage.
/// On desktop Macs (no battery) `isAvailable == false`.
public final class BatteryProvider: MetricProvider, @unchecked Sendable {
    public let id: MetricID = .battery
    public let cost: SamplingCost = .medium

    public init() {}

    public var isAvailable: Bool {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return false }
        return !list.isEmpty
    }

    public func sample() -> MetricSample? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
              let source = sources.first,
              let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue()
                as? [String: Any]
        else { return nil }

        let current = (desc[kIOPSCurrentCapacityKey] as? Int) ?? 0
        let maxCap = (desc[kIOPSMaxCapacityKey] as? Int) ?? 100
        let fraction = maxCap > 0 ? Double(current) / Double(maxCap) : 0

        let isCharging = (desc[kIOPSIsChargingKey] as? Bool) ?? false
        let timeToEmpty = (desc[kIOPSTimeToEmptyKey] as? Int) ?? -1
        let timeToFull = (desc[kIOPSTimeToFullChargeKey] as? Int) ?? -1

        var detail: [String: Double] = [
            "charging": isCharging ? 1 : 0,
            "timeToEmpty": Double(timeToEmpty),
            "timeToFull": Double(timeToFull),
            "currentCapacity": Double(current),
            "maxCapacity": Double(maxCap)
        ]

        // Health / cycle / temperature from the AppleSmartBattery IORegistry entry.
        if let smart = readSmartBattery() {
            detail.merge(smart) { _, new in new }
        }

        return MetricSample(value: fraction, unit: .fraction, detail: detail)
    }

    private func readSmartBattery() -> [String: Double]? {
        let matching = IOServiceMatching("AppleSmartBattery")
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0)
                == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any]
        else { return nil }

        var out: [String: Double] = [:]
        if let cycle = dict["CycleCount"] as? Int { out["cycleCount"] = Double(cycle) }
        // Fallback estimate when IOPS reports -1: minutes to empty (discharging) or
        // to full (charging); 65535 means "no estimate".
        if let remaining = dict["TimeRemaining"] as? Int, remaining > 0, remaining < 65535 {
            out["smartTimeRemaining"] = Double(remaining)
        }
        if let designCap = dict["DesignCapacity"] as? Int,
           let maxCap = dict["AppleRawMaxCapacity"] as? Int ?? dict["MaxCapacity"] as? Int,
           designCap > 0 {
            out["healthPercent"] = Double(maxCap) / Double(designCap) * 100
        }
        if let temp = dict["Temperature"] as? Int {
            // AppleSmartBattery temperature is in 1/100 °C.
            out["temperature"] = Double(temp) / 100
        }
        if let voltage = dict["Voltage"] as? Int { out["voltage"] = Double(voltage) / 1000 }
        if let amperage = dict["Amperage"] as? Int { out["amperage"] = Double(amperage) }
        return out
    }
}
