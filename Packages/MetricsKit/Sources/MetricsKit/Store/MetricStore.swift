import Foundation

/// Keeps a fixed-capacity ring buffer per metric. Sparkline history and the latest value
/// are read from here. Fixed capacity means near-zero allocation on the hot path (no heap
/// allocation per sample), aligned with the lightweight goal.
///
/// Access is synchronized because the engine writes on its sampling queue while app and
/// CLI consumers may read history from another thread.
public final class MetricStore: @unchecked Sendable {
    /// Samples kept per metric (e.g. 300 samples ≈ 5 min @1s).
    public let capacity: Int

    private var buffers: [MetricID: RingBuffer<MetricSample>] = [:]
    private let lock = NSLock()

    public init(capacity: Int = 300) {
        self.capacity = capacity
    }

    public func append(_ sample: MetricSample, for id: MetricID) {
        lock.lock()
        defer { lock.unlock() }
        if buffers[id] == nil {
            buffers[id] = RingBuffer(capacity: capacity)
        }
        buffers[id]?.append(sample)
    }

    /// Most recent sample.
    public func latest(_ id: MetricID) -> MetricSample? {
        lock.lock()
        defer { lock.unlock() }
        return buffers[id]?.last
    }

    /// The newest `count` samples, oldest-to-newest (for sparklines).
    public func history(_ id: MetricID, count: Int) -> [MetricSample] {
        lock.lock()
        defer { lock.unlock() }
        guard let buffer = buffers[id] else { return [] }
        let all = buffer.elements
        if all.count <= count { return all }
        return Array(all.suffix(count))
    }

    /// Full history.
    public func history(_ id: MetricID) -> [MetricSample] {
        lock.lock()
        defer { lock.unlock() }
        return buffers[id]?.elements ?? []
    }
}

/// Simple fixed-capacity ring buffer.
struct RingBuffer<Element> {
    private var storage: [Element?]
    private var head = 0        // next write index
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

    /// Elements oldest-to-newest.
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
