import Foundation

final class LazyArrayCursor {
    let scanner: MsgPackScanner
    let start: UnsafeRawPointer
    let count: Int

    private var materialised: [MsgPackValue]
    private var nextElement: UnsafeRawPointer

    /// Number of elements that have been materialised so far. Exposed
    /// so tests can assert lazy invariants (e.g. "only the first K
    /// elements were walked").
    var consumedCount: Int { materialised.count }

    init(scanner: MsgPackScanner, start: UnsafeRawPointer, count: Int) {
        self.scanner = scanner
        self.start = start
        self.count = count
        nextElement = start
        materialised = []
        materialised.reserveCapacity(count)
    }

    func element(at index: Int) -> MsgPackValue {
        precondition(index >= 0 && index < count, "LazyArrayCursor element(at:) out of range \(index) vs count \(count)")
        while materialised.count <= index {
            scanner.seek(to: nextElement)
            materialised.append(scanner.scanLazy())
            nextElement = scanner.currentPointer
        }
        return materialised[index]
    }

    func elements() -> [MsgPackValue] {
        while materialised.count < count {
            scanner.seek(to: nextElement)
            materialised.append(scanner.scanLazy())
            nextElement = scanner.currentPointer
        }
        return materialised
    }
}

final class LazyMapCursor {
    let scanner: MsgPackScanner
    let start: UnsafeRawPointer
    let pairCount: Int

    private var pairs: [(MsgPackValue, MsgPackValue)]
    private var stringIndex: [String: Int]
    /// Number of (key, value) pairs already walked. Exposed so tests
    /// can assert lazy invariants (e.g. "only the first K pairs were
    /// walked").
    private(set) var consumedPairs: Int
    private var nextPair: UnsafeRawPointer

    init(scanner: MsgPackScanner, start: UnsafeRawPointer, pairCount: Int) {
        self.scanner = scanner
        self.start = start
        self.pairCount = pairCount
        pairs = []
        pairs.reserveCapacity(pairCount)
        stringIndex = [:]
        stringIndex.reserveCapacity(pairCount)
        consumedPairs = 0
        nextPair = start
    }

    private func consumeNext() -> (MsgPackValue, MsgPackValue, String?) {
        scanner.seek(to: nextPair)
        let k = scanner.scanLazy()
        let v = scanner.scanLazy()
        nextPair = scanner.currentPointer
        consumedPairs += 1
        pairs.append((k, v))
        var keyString: String?
        if case let .literal(.str(buf)) = k.content, let s = String._tryFromUTF8(buf) {
            if stringIndex[s] == nil {
                stringIndex[s] = pairs.count - 1
            }
            keyString = s
        }
        return (k, v, keyString)
    }

    /// Walk forward through the payload until the target string key is
    /// found or the map is exhausted. Already-walked entries stay
    /// cached so a second lookup is O(1).
    func value(forStringKey key: String) -> MsgPackValue? {
        if let idx = stringIndex[key] {
            return pairs[idx].1
        }
        while consumedPairs < pairCount {
            let (_, v, keyString) = consumeNext()
            if keyString == key {
                return v
            }
        }
        return nil
    }

    /// All entries in encountered order, as a flat [k, v, k, v, ...]
    /// array. Triggers a complete walk of the payload.
    func entries() -> [MsgPackValue] {
        while consumedPairs < pairCount {
            _ = consumeNext()
        }
        var arr: [MsgPackValue] = []
        arr.reserveCapacity(pairCount * 2)
        for (k, v) in pairs {
            arr.append(k)
            arr.append(v)
        }
        return arr
    }

    /// All string-typed keys discovered so far. Forces a complete walk
    /// of the payload.
    func allStringKeys() -> [String] {
        while consumedPairs < pairCount {
            _ = consumeNext()
        }
        return Array(stringIndex.keys)
    }

    func contains(stringKey key: String) -> Bool {
        value(forStringKey: key) != nil
    }
}
