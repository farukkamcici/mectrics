import Foundation

/// Metrik başına sabit kapasiteli halka tampon (ring buffer) tutar.
/// Sparkline geçmişi ve son değer buradan okunur. Sabit kapasite = sıfıra yakın
/// tahsis (hot path'te heap allocation yok) → hafiflik hedefiyle uyumlu.
///
/// Erişim tek seri kuyruktan yapıldığı varsayılır (engine'in sampling kuyruğu).
/// UI okumaları da aynı kuyruk üzerinden ana thread'e publish edilir.
public final class MetricStore: @unchecked Sendable {
    /// Metrik başına saklanacak örnek sayısı (ör. 300 örnek ≈ 5 dk @1s).
    public let capacity: Int

    private var buffers: [MetricID: RingBuffer<MetricSample>] = [:]

    public init(capacity: Int = 300) {
        self.capacity = capacity
    }

    public func append(_ sample: MetricSample, for id: MetricID) {
        if buffers[id] == nil {
            buffers[id] = RingBuffer(capacity: capacity)
        }
        buffers[id]?.append(sample)
    }

    /// En güncel örnek.
    public func latest(_ id: MetricID) -> MetricSample? {
        buffers[id]?.last
    }

    /// En yeni `count` örnek, eskiden yeniye sıralı (sparkline için).
    public func history(_ id: MetricID, count: Int) -> [MetricSample] {
        guard let buffer = buffers[id] else { return [] }
        let all = buffer.elements
        if all.count <= count { return all }
        return Array(all.suffix(count))
    }

    /// Tüm geçmiş.
    public func history(_ id: MetricID) -> [MetricSample] {
        buffers[id]?.elements ?? []
    }
}

/// Basit sabit-kapasiteli halka tampon.
struct RingBuffer<Element> {
    private var storage: [Element?]
    private var head = 0        // bir sonraki yazılacak indeks
    private var filled = 0
    let capacity: Int

    init(capacity: Int) {
        self.capacity = max(1, capacity)
        self.storage = Array(repeating: nil, count: self.capacity)
    }

    mutating func append(_ element: Element) {
        storage[head] = element
        head = (head + 1) % capacity
        filled = min(filled + 1, capacity)
    }

    var last: Element? {
        guard filled > 0 else { return nil }
        let idx = (head - 1 + capacity) % capacity
        return storage[idx]
    }

    /// Eskiden yeniye sıralı elemanlar.
    var elements: [Element] {
        guard filled > 0 else { return [] }
        var result: [Element] = []
        result.reserveCapacity(filled)
        let start = (head - filled + capacity) % capacity
        for i in 0..<filled {
            if let e = storage[(start + i) % capacity] {
                result.append(e)
            }
        }
        return result
    }
}
