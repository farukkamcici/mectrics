import Foundation

/// How hard macOS says it is holding the chip back.
///
/// This is `ProcessInfo.ThermalState` — the system's own verdict, not a sensor
/// reading. A temperature says how hot a part is; this says whether the machine is
/// actually being slowed down, which is the cost a person feels. On Apple silicon the
/// state covers the whole package, so a throttled GPU is reported here too: there is
/// no separate public GPU throttling signal, and reading clock frequencies would mean
/// private interfaces this app does not use.
public enum ThermalPressureLevel: Int, CaseIterable, Equatable, Sendable {
    case nominal
    case fair
    case serious
    case critical

    public init(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal: self = .nominal
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        @unknown default: self = .nominal
        }
    }

    public static var current: Self {
        Self(ProcessInfo.processInfo.thermalState)
    }
}

/// `kern.memorystatus_vm_pressure_level` — the kernel's own verdict on memory.
///
/// Distinct from the used-memory percentage: memory can be nearly full while the
/// kernel is under no pressure at all, and the percentage alone cannot tell those
/// apart. The raw values are the kernel's own, not a scale invented here, which is
/// why they skip 3.
public enum MemoryPressureLevel: Int, CaseIterable, Equatable, Sendable {
    case normal = 1
    case warning = 2
    case critical = 4
}

/// Resolves every native system signal from one sampling pass, so the app, the CLI,
/// and the one-shot health report all read the same conditions the same way.
public enum SystemConditionSource {
    public static func readings(
        latest: [MetricID: MetricSample],
        thermalLevel: ThermalPressureLevel = .current
    ) -> [SystemAlertSignal: SystemConditionReading] {
        // Thermal pressure comes from ProcessInfo rather than a provider, so it is
        // always readable — there is no hardware to be missing.
        var readings: [SystemAlertSignal: SystemConditionReading] = [
            .thermalPressure: SystemConditionReading(
                .thermalPressure,
                value: Double(thermalLevel.rawValue)
            )
        ]
        if let pressure = latest[.memory]?.detail["pressureLevel"] {
            readings[.memoryPressure] = SystemConditionReading(
                .memoryPressure,
                value: pressure
            )
        }
        if let free = latest[.disk]?.detail["free"] {
            readings[.diskAvailableCapacity] = SystemConditionReading(
                .diskAvailableCapacity,
                value: free
            )
        }
        if let service = latest[.battery]?.detail["serviceRecommended"] {
            readings[.batteryService] = SystemConditionReading(
                .batteryService,
                value: service
            )
        }
        return readings
    }
}
