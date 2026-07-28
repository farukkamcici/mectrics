import Foundation

/// Her metrik kaynağının uyguladığı sözleşme.
///
/// Provider'lar durum tutabilir (ör. CPU/ağ ardışık iki örnek farkı ister), bu yüzden
/// `class` (reference type). Örnekleme her zaman aynı seri kuyrukta yapılır → thread-safe
/// olmaları gerekmez; bu nedenle `@unchecked Sendable`.
public protocol MetricProvider: AnyObject {
    var id: MetricID { get }

    /// Bu donanım/izin bu makinede mevcut mu? (ör. fansız MacBook Air'de fan yok.)
    var isAvailable: Bool { get }

    /// Scheduler'ın frekans kararı için maliyet sınıfı.
    var cost: SamplingCost { get }

    /// Tek örnekleme. Başarısız olursa `nil` döner (donanım yok / geçici hata).
    func sample() -> MetricSample?
}

public extension MetricProvider {
    var isAvailable: Bool { true }
    var cost: SamplingCost { .light }
}
