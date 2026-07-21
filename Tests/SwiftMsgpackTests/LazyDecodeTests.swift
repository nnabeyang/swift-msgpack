import XCTest
@testable import SwiftMsgpack

final class LazyDecodeTests: XCTestCase {
    let encoder = MsgPackEncoder()

    private func lazyDecode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = MsgPackDecoder(options: .lazyScan)
        return try decoder.decode(type, from: data)
    }

    func testPartialMapDecode() throws {
        struct Trio: Codable, Equatable {
            let a: Int
            let b: Int
            let c: Int
        }
        struct Pair: Codable, Equatable {
            let a: Int
            let c: Int
        }
        let data = try encoder.encode(Trio(a: 1, b: 2, c: 3))
        XCTAssertEqual(try lazyDecode(Pair.self, from: data), Pair(a: 1, c: 3))
    }

    func testDeeplyNestedMap() throws {
        struct Leaf: Codable, Equatable { let value: Int }
        struct N3: Codable, Equatable { let leaf: Leaf }
        struct N2: Codable, Equatable { let inner: N3 }
        struct N1: Codable, Equatable { let inner: N2 }

        let original = N1(inner: N2(inner: N3(leaf: Leaf(value: 42))))
        let data = try encoder.encode(original)
        XCTAssertEqual(try lazyDecode(N1.self, from: data), original)
    }

    func testArrayOfMaps() throws {
        struct Item: Codable, Equatable {
            let key: String
            let value: Int
        }
        let arr = [
            Item(key: "a", value: 1),
            Item(key: "b", value: 2),
            Item(key: "c", value: 3),
        ]
        let data = try encoder.encode(arr)
        XCTAssertEqual(try lazyDecode([Item].self, from: data), arr)
    }

    func testRepeatedKeyDecodeIsStable() throws {
        struct DoubleRead: Decodable, Equatable {
            let first: Int
            let second: Int

            init(first: Int, second: Int) {
                self.first = first
                self.second = second
            }

            enum CodingKeys: String, CodingKey {
                case x
            }

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                first = try c.decode(Int.self, forKey: .x)
                second = try c.decode(Int.self, forKey: .x)
            }
        }
        struct Source: Codable { let x: Int }
        let data = try encoder.encode(Source(x: 99))
        let decoded = try lazyDecode(DoubleRead.self, from: data)
        XCTAssertEqual(decoded, DoubleRead(first: 99, second: 99))
    }

    func testLazyMatchesEagerForAnyCodable() throws {
        let input: [AnyCodable: AnyCodable] = [
            .init("k1"): .init(1),
            .init("k2"): .init("two"),
            .init("k3"): .init([AnyCodable(3.14), .init(true)]),
        ]
        let data = try encoder.encode(input)
        let eager = try MsgPackDecoder().decode([AnyCodable: AnyCodable].self, from: data)
        let lazy = try lazyDecode([AnyCodable: AnyCodable].self, from: data)
        XCTAssertEqual(eager, lazy)
    }

    func testLazyMapRejectsArrayPayload() throws {
        // fixarray of size 2 — not a map
        let data = Data([0x92, 0x01, 0x02])
        XCTAssertThrowsError(try lazyDecode([String: Int].self, from: data)) { error in
            guard case DecodingError.typeMismatch = error else {
                XCTFail("expected DecodingError.typeMismatch, got \(error)")
                return
            }
        }
    }

    func testReverseOrderNestedDecodeForcesCursorReseek() throws {
        struct Source: Encodable {
            let first: [Int]
            let last: [Int]
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: Key.self)
                try c.encode(first, forKey: .first)
                try c.encode(last, forKey: .last)
            }

            enum Key: String, CodingKey { case first, last }
        }
        struct ReversedDecode: Decodable, Equatable {
            let first: [Int]
            let last: [Int]
            init(first: [Int], last: [Int]) {
                self.first = first
                self.last = last
            }

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: Key.self)
                // Decode in reverse on-wire order. The lazy path must
                // seek backward through the payload to materialise the
                // first nested array after already materialising the
                // last one.
                last = try c.decode([Int].self, forKey: .last)
                first = try c.decode([Int].self, forKey: .first)
            }

            enum Key: String, CodingKey { case first, last }
        }

        let data = try encoder.encode(Source(first: [1, 2, 3], last: [10, 20, 30]))
        XCTAssertEqual(
            try lazyDecode(ReversedDecode.self, from: data),
            ReversedDecode(first: [1, 2, 3], last: [10, 20, 30])
        )
    }

    func testPartialMapSkipsUnreferencedNestedPayload() throws {
        // Encoded shape: { a: 1, big: [1..100], c: 3 }
        struct Source: Encodable {
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: Key.self)
                try c.encode(1, forKey: .a)
                try c.encode(Array(0 ..< 100), forKey: .big)
                try c.encode(3, forKey: .c)
            }

            enum Key: String, CodingKey { case a, big, c }
        }
        // Target struct that never reads `big`.
        struct Pair: Decodable, Equatable {
            let a: Int
            let c: Int
        }
        let data = try encoder.encode(Source())
        XCTAssertEqual(try lazyDecode(Pair.self, from: data), Pair(a: 1, c: 3))
    }

    func testLazyArrayOfMapsReverseAccess() throws {
        struct Inner: Codable, Equatable {
            let id: Int
            let label: String
        }
        struct Outer: Decodable, Equatable {
            let last: Inner
            let middle: Inner
            let first: Inner

            init(last: Inner, middle: Inner, first: Inner) {
                self.last = last
                self.middle = middle
                self.first = first
            }

            init(from decoder: Decoder) throws {
                var c = try decoder.unkeyedContainer()
                let a = try c.decode(Inner.self)
                let b = try c.decode(Inner.self)
                let cc = try c.decode(Inner.self)
                // Reorder to force later access to the earlier-encoded
                // element — exercises cursor independence across sibling
                // lazy maps.
                first = a
                middle = b
                last = cc
            }
        }
        let payload = [
            Inner(id: 1, label: "a"),
            Inner(id: 2, label: "b"),
            Inner(id: 3, label: "c"),
        ]
        let data = try encoder.encode(payload)
        let decoded = try lazyDecode(Outer.self, from: data)
        XCTAssertEqual(
            decoded,
            Outer(
                last: Inner(id: 3, label: "c"),
                middle: Inner(id: 2, label: "b"),
                first: Inner(id: 1, label: "a")
            )
        )
    }

    func testLazyDecodesExtAsMapValue() throws {
        let map: [String: MsgPackTimestamp] = [
            "t32": MsgPackTimestamp(seconds: 0x4B6B_34AB, nanoseconds: 0),
            "t64": MsgPackTimestamp(seconds: 1_234_567_890, nanoseconds: 42),
        ]
        let data = try encoder.encode(map)
        let decoded = try lazyDecode([String: MsgPackTimestamp].self, from: data)
        XCTAssertEqual(decoded, map)
    }

    private struct OrderedEntries: Encodable {
        let entries: [(String, String)]
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: Key.self)
            for (k, v) in entries {
                try c.encode(v, forKey: Key(stringValue: k))
            }
        }

        struct Key: CodingKey {
            let stringValue: String
            var intValue: Int? { nil }
            init(stringValue: String) { self.stringValue = stringValue }
            init?(intValue _: Int) { nil }
        }
    }

    func testLazyMapCursorOnlyWalksToTargetKey() throws {
        let entries: [(String, String)] = (0 ..< 100).map { ("key_\($0)", "v\($0)") }
        let data = try encoder.encode(OrderedEntries(entries: entries))

        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let scanner = MsgPackScanner(source: data, ptr: raw.baseAddress!, count: raw.count)
            guard case let .lazyMap(cursor) = scanner.scanLazy().content else {
                XCTFail("expected .lazyMap at root")
                return
            }
            XCTAssertEqual(cursor.pairCount, 100)
            XCTAssertEqual(cursor.consumedPairs, 0)

            XCTAssertNotNil(cursor.value(forStringKey: "key_4"))
            XCTAssertEqual(cursor.consumedPairs, 5, "first hit at key_4 should walk 5 pairs")

            XCTAssertNotNil(cursor.value(forStringKey: "key_4"))
            XCTAssertEqual(cursor.consumedPairs, 5, "second lookup of same key must hit cache")

            XCTAssertNotNil(cursor.value(forStringKey: "key_2"))
            XCTAssertEqual(cursor.consumedPairs, 5, "earlier key must hit cache")

            XCTAssertNotNil(cursor.value(forStringKey: "key_10"))
            XCTAssertEqual(cursor.consumedPairs, 11, "later key extends walk by 6")

            XCTAssertNil(cursor.value(forStringKey: "no_such_key"))
            XCTAssertEqual(cursor.consumedPairs, 100, "missing key forces full walk")
        }
    }

    func testLazyArrayCursorOnlyMaterialisesToIndex() throws {
        let arr = Array(0 ..< 20)
        let data = try encoder.encode(arr)

        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let scanner = MsgPackScanner(source: data, ptr: raw.baseAddress!, count: raw.count)
            guard case let .lazyArray(cursor) = scanner.scanLazy().content else {
                XCTFail("expected .lazyArray at root")
                return
            }
            XCTAssertEqual(cursor.count, 20)
            XCTAssertEqual(cursor.consumedCount, 0)

            _ = cursor.element(at: 5)
            XCTAssertEqual(cursor.consumedCount, 6, "first access at index 5 walks 6 elements")

            _ = cursor.element(at: 3)
            XCTAssertEqual(cursor.consumedCount, 6, "back-fill access must hit cache")

            _ = cursor.element(at: 10)
            XCTAssertEqual(cursor.consumedCount, 11, "later access extends walk by 5")
        }
    }

    func testLazyEmptyMap() throws {
        // fixmap of size 0
        let data = Data([0x80])
        XCTAssertEqual(try lazyDecode([String: String].self, from: data), [:])
    }

    func testLazyNilValueInMap() throws {
        struct Source: Encodable {
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: K.self)
                try c.encodeNil(forKey: K.x)
                try c.encode(42, forKey: K.y)
            }

            enum K: String, CodingKey { case x, y }
        }
        struct Target: Decodable, Equatable {
            let x: Int?
            let y: Int
        }
        let data = try encoder.encode(Source())
        XCTAssertEqual(try lazyDecode(Target.self, from: data), Target(x: nil, y: 42))
    }

    func testLazyDecodeWithNonStringKeyEntries() throws {
        // Mix of Int and String keys; the Codable decode path drops
        // non-String keys when targeting [String: Int]. Make sure the
        // lazy path follows the same convention as eager.
        let mixed: [AnyCodable: AnyCodable] = [
            .init("ok"): .init(7),
            .init(99): .init(88),
            .init("alsoOk"): .init(11),
        ]
        let data = try encoder.encode(mixed)
        let eager = try MsgPackDecoder().decode([String: Int].self, from: data)
        let lazy = try lazyDecode([String: Int].self, from: data)
        XCTAssertEqual(eager, lazy)
        XCTAssertEqual(lazy["ok"], 7)
        XCTAssertEqual(lazy["alsoOk"], 11)
    }
}
