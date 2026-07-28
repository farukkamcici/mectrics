import Foundation
import IOKit

/// Bağlı Bluetooth cihazlarının pil seviyelerini IORegistry'den okur (best-effort).
///
/// Birçok cihaz (Magic Mouse/Keyboard, bazı kulaklıklar) IORegistry'de `BatteryPercent`
/// özelliği yayınlar. `value` = en düşük cihaz pili (0...1) — "en kritik cihaz" göstergesi.
/// Ayrıntı: deviceCount ve device0..N pil yüzdeleri.
///
/// Not: Pil yayını cihaza göre değişkendir; hiç cihaz bulunmazsa modül kullanılamaz sayılır
/// (menü çubuğunda görünmez). Cihaz adları ileride ayrı bir kanalla eklenecek.
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

    /// IORegistry'yi özyinelemeli tarayıp `BatteryPercent` içeren girdilerin yüzdelerini toplar.
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
