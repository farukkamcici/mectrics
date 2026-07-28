import Foundation

/// Metrik toplama koordinatörü.
///
/// - Kayıtlı provider'ları seri bir arka plan kuyruğunda periyodik örnekler.
/// - Sonuçları `MetricStore`'a yazar (ring buffer / geçmiş).
/// - Her döngü sonunda `onCycle` closure'ını **ana thread**'de çağırır → UI güncellemesi.
///
/// UI'dan bağımsızdır (SwiftUI import etmez); CLI ve app aynı motoru kullanır.
public final class MetricsEngine: @unchecked Sendable {
    public let store: MetricStore

    private var providers: [MetricProvider] = []
    private let queue = DispatchQueue(label: "com.mectrics.sampling", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var policy: SamplingPolicy
    private var cycleCount = 0

    /// Her örnekleme döngüsünden sonra ana thread'de çağrılır.
    /// Parametre: bu döngüde güncellenen metriklerin son değerleri.
    public var onCycle: (@Sendable ([MetricID: MetricSample]) -> Void)?

    public init(store: MetricStore = MetricStore(),
                policy: SamplingPolicy = .default) {
        self.store = store
        self.policy = policy
    }

    /// Mevcut (kullanılabilir) provider'ları kaydeder.
    public func register(_ providers: [MetricProvider]) {
        queue.async { [weak self] in
            guard let self else { return }
            self.providers = providers.filter { $0.isAvailable }
        }
    }

    public func start(onBattery: Bool = false) {
        queue.async { [weak self] in
            guard let self else { return }
            self.scheduleTimer(onBattery: onBattery)
        }
    }

    public func stop() {
        queue.async { [weak self] in
            self?.timer?.cancel()
            self?.timer = nil
        }
    }

    /// Güç durumu değişince aralığı yeniden ayarlar.
    public func updatePowerState(onBattery: Bool) {
        queue.async { [weak self] in
            guard let self, self.timer != nil else { return }
            self.scheduleTimer(onBattery: onBattery)
        }
    }

    private func scheduleTimer(onBattery: Bool) {
        timer?.cancel()
        let interval = onBattery ? policy.onBatteryInterval : policy.onACInterval
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(100))
        t.setEventHandler { [weak self] in
            self?.tick()
        }
        timer = t
        t.resume()
    }

    private func tick() {
        cycleCount &+= 1
        let runHeavy = cycleCount % max(1, policy.heavyEveryNCycles) == 0
        var updated: [MetricID: MetricSample] = [:]

        for provider in providers {
            if provider.cost == .heavy && !runHeavy { continue }
            if let sample = provider.sample() {
                store.append(sample, for: provider.id)
                updated[provider.id] = sample
            }
        }

        DispatchQueue.main.async { [onCycle] in
            onCycle?(updated)
        }
    }
}
