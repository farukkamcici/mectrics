import Foundation

/// Uygulamadaki her metrik modülünün stabil kimliği.
/// UI, ayarlar ve App Group snapshot'ları bu değerlerle anahtarlanır.
public enum MetricID: String, CaseIterable, Codable, Sendable {
    case cpu
    case memory
    case battery
    case network
    case disk
    case gpu
    case sensors
    case fans
    case bluetooth
    case clock

    /// Kullanıcıya gösterilecek kısa ad.
    public var displayName: String {
        switch self {
        case .cpu: return "CPU"
        case .memory: return "Bellek"
        case .battery: return "Pil"
        case .network: return "Ağ"
        case .disk: return "Disk"
        case .gpu: return "GPU"
        case .sensors: return "Sensörler"
        case .fans: return "Fanlar"
        case .bluetooth: return "Bluetooth"
        case .clock: return "Saat"
        }
    }
}

/// Bir provider'ın örnekleme maliyeti — scheduler bunu frekans kararında kullanır.
public enum SamplingCost: Sendable {
    case light   // host_statistics türü ucuz çağrılar (CPU, RAM)
    case medium  // IOKit sorguları (pil, disk, ağ)
    case heavy   // SMC/sensör/GPU — seyrek örneklenir
}
