import Foundation
import Darwin

/// CPU kullanımını Mach `host_processor_info` ile per-core tick sayaçlarından hesaplar.
///
/// Yöntem: her çekirdek için user+system+nice+idle "tick" sayaçları kümülatiftir.
/// İki ardışık örnek arasındaki delta'lardan busy oranı = (Δbusy) / (Δtotal).
/// İlk örnek referans alınır; ikinci örnekten itibaren gerçek değer üretilir.
public final class CPUProvider: MetricProvider, @unchecked Sendable {
    public let id: MetricID = .cpu
    public let cost: SamplingCost = .light

    private var previousTicks: [[UInt32]] = []

    public init() {}

    public func sample() -> MetricSample? {
        guard let cores = readPerCoreTicks() else { return nil }

        // İlk örnek: referansı sakla, henüz oran üretme (0 döndür).
        guard previousTicks.count == cores.count, !previousTicks.isEmpty else {
            previousTicks = cores
            return MetricSample(value: 0, unit: .fraction,
                                detail: ["coreCount": Double(cores.count)])
        }

        var perCoreUsage: [Double] = []
        perCoreUsage.reserveCapacity(cores.count)
        var totalBusyDelta: Double = 0
        var totalTickDelta: Double = 0

        for i in 0..<cores.count {
            let cur = cores[i]
            let prev = previousTicks[i]
            // CPU_STATE_USER=0, SYSTEM=1, IDLE=2, NICE=3
            let user   = Double(cur[0] &- prev[0])
            let system = Double(cur[1] &- prev[1])
            let idle   = Double(cur[2] &- prev[2])
            let nice   = Double(cur[3] &- prev[3])
            let busy = user + system + nice
            let total = busy + idle
            let usage = total > 0 ? busy / total : 0
            perCoreUsage.append(usage)
            totalBusyDelta += busy
            totalTickDelta += total
        }

        previousTicks = cores

        let aggregate = totalTickDelta > 0 ? totalBusyDelta / totalTickDelta : 0

        var detail: [String: Double] = ["coreCount": Double(cores.count)]
        for (i, usage) in perCoreUsage.enumerated() {
            detail["core\(i)"] = usage
        }

        return MetricSample(value: aggregate, unit: .fraction, detail: detail)
    }

    /// Her çekirdek için [user, system, idle, nice] tick dizisini döndürür.
    private func readPerCoreTicks() -> [[UInt32]]? {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &cpuCount,
            &info,
            &infoCount
        )
        guard result == KERN_SUCCESS, let info else { return nil }

        // Bittiğinde çekirdek belleğini geri ver.
        defer {
            let size = vm_size_t(UInt(infoCount) * UInt(MemoryLayout<integer_t>.stride))
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), size)
        }

        let states = Int(CPU_STATE_MAX) // 4
        var cores: [[UInt32]] = []
        cores.reserveCapacity(Int(cpuCount))
        for core in 0..<Int(cpuCount) {
            let base = core * states
            let ticks = (0..<states).map { UInt32(bitPattern: info[base + $0]) }
            cores.append(ticks)
        }
        return cores
    }
}
