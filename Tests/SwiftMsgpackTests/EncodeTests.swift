import XCTest
@testable import SwiftMsgpack

final class EncodeTests: XCTestCase {
    private let encoder = MsgPackEncoder()

    private func t<X: Encodable>(in input: X, type _: X.Type, out: String, file: StaticString = #filePath, line: UInt = #line) {
        do {
            let actual = try encoder.encode(input)
            XCTAssertEqual(actual.hexDescription, out, file: file, line: line)
        } catch {
            XCTFail("unexpected error: \(error)", file: file, line: line)
        }
    }

    func testEncode() {
        t(in: nil, type: Int?.self, out: "c0")
        t(in: 0x59, type: UInt8.self, out: "59")
        t(in: false, type: Bool.self, out: "c2")
        t(in: true, type: Bool.self, out: "c3")
        t(in: SS2(a: "Hello"), type: SS2.self, out: "c7050348656c6c6f")
        t(in: MsgPackTimestamp(seconds: 9_223_372_036_854_775_807, nanoseconds: 999_999_999), type: MsgPackTimestamp.self, out: "c70cff3b9ac9ff7fffffffffffffff")
        t(in: MsgPackTimestamp(seconds: -9_223_372_036_854_775_808, nanoseconds: 0), type: MsgPackTimestamp.self, out: "c70cff000000008000000000000000")
        t(in: 0x80, type: UInt8.self, out: "cc80")
        t(in: 0x4B6B, type: UInt16.self, out: "cd4b6b")
        t(in: 0x4B6B34, type: UInt32.self, out: "ce004b6b34")
        t(in: 0x4B_6B34_ABCC, type: UInt64.self, out: "cf0000004b6b34abcc")
        t(in: 0x4B_6B34_ABCC, type: UInt.self, out: "cf0000004b6b34abcc")
        t(in: -0x7F, type: Int8.self, out: "d081")
        t(in: -0x4B6B, type: Int16.self, out: "d1b495")
        t(in: -0x4B6B34, type: Int32.self, out: "d2ffb494cc")
        t(in: -0x4B_6B34_ABCC, type: Int64.self, out: "d3ffffffb494cb5434")
        t(in: -0x4B_6B34_ABCC, type: Int.self, out: "d3ffffffb494cb5434")
        t(in: 3.14, type: Float.self, out: "ca4048f5c3")
        t(in: 2.34, type: Double.self, out: "cb4002b851eb851eb8")
        t(in: "Hello", type: String.self, out: "a548656c6c6f")
        t(in: "abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz", type: String.self, out: "d9686162636465666768696a6b6c6d6e6f707172737475767778797a6162636465666768696a6b6c6d6e6f707172737475767778797a6162636465666768696a6b6c6d6e6f707172737475767778797a6162636465666768696a6b6c6d6e6f707172737475767778797a")
        t(in: nil, type: [Int8]?.self, out: "c0")
        t(in: [0x12, 0x34, 0x56], type: [UInt8].self, out: "93123456")
        t(in: -0x20, type: Int8.self, out: "e0")
        t(in: .init(X: 0x12, Y: 0x34), type: Pair.self, out: "82a15812a15934")
        t(in: .init(X: 0x12, Y: 0x34), type: PairArray.self, out: "921234")
        t(in: Opacity(a: 0x3D), type: Opacity.self, out: "d4013d")
        t(in: Position(x: 0x12, y: 0x34), type: Position.self, out: "d5021234")
        t(in: MsgPackTimestamp(seconds: 1_655_888_192, nanoseconds: 0), type: MsgPackTimestamp.self, out: "d6ff62b2d940")
        t(in: MsgPackTimestamp(seconds: 4_294_967_295, nanoseconds: 0), type: MsgPackTimestamp.self, out: "d6ffffffffff")
        t(in: MsgPackTimestamp(seconds: 0, nanoseconds: 0), type: MsgPackTimestamp.self, out: "d6ff00000000")
        t(in: MsgPackTimestamp(seconds: 1_655_888_192, nanoseconds: 999_999_999), type: MsgPackTimestamp.self, out: "d7ffee6b27fc62b2d940")
        t(in: MsgPackTimestamp(seconds: 17_179_869_183, nanoseconds: 999_999_999), type: MsgPackTimestamp.self, out: "d7ffee6b27ffffffffff")
        t(in: MsgPackTimestamp(seconds: 0, nanoseconds: 1), type: MsgPackTimestamp.self, out: "d7ff0000000400000000")
        t(in: Ext16(a: [0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF, 0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF]), type: Ext16.self, out: "d8050123456789abcdef0123456789abcdef")
        // UnkeyedEncodingContainer
        t(in: SS(a: ["abc", "xyz", "ddd"]), type: SS.self, out: "93a3616263a378797aa3646464")
        t(in: IS(a: [-0x20, -0x1F]), type: IS.self, out: "92e0e1")
        t(in: FS(a: [2.34, 3.14]), type: FS.self, out: "92ca4015c28fca4048f5c3")
        t(in: BS(a: [false, true]), type: BS.self, out: "92c2c3")
        // KeyedEncodingContainer
        t(in: Pair(X: 0x12, Y: 0x34), type: Pair.self, out: "82a15812a15934")
        t(in: PairStr(X: "abc", Y: "def"), type: PairStr.self, out: "82a158a3616263a159a3646566")
        t(in: PairInt(X: -0x20, Y: -0x1F), type: PairInt.self, out: "82a158e0a159e1")
        t(in: [:], type: [String: Small].self, out: "80")
        t(in: [], type: [String].self, out: "90")
        t(in: nil, type: [String]?.self, out: "c0")
    }
}

extension Data {
    var hexDescription: String {
        reduce("") { $0 + String(format: "%02x", $1) }
    }
}

struct All: Codable, Equatable {
    let bool: Bool
    let int: Int
    let int8: Int8
    let int16: Int16
    let int32: Int32
    let int64: Int64
    let uint: UInt
    let uint8: UInt8
    let uint16: UInt16
    let uint32: UInt32
    let uint64: UInt64
    let float: Float
    let double: Double
    let string: String
    let stringM: String
    let map: [String: Small]
    let mapP: [String: Small?]
    let floatMap: [Float: String]
    let nilArray: [String]?
    let emptyArray: [Small]
    let bytes: Data
    let superCodable: SuperCodable
    let ext1: Opacity
    let time32: MsgPackTimestamp
    let time32_min: MsgPackTimestamp
    let time64: MsgPackTimestamp
    let time64_min: MsgPackTimestamp
    let time96: MsgPackTimestamp
    let time96_min: MsgPackTimestamp
}

extension All {
    static var value: All {
        .init(
            bool: true,
            int: -0x4B_6B34_ABCC,
            int8: -0x35,
            int16: -0x4B6B,
            int32: -0x4B6B34,
            int64: -0x4B_6B34_ABCC,
            uint: 0x4B_6B34_ABCC,
            uint8: 0x35,
            uint16: 0x4B6B,
            uint32: 0x4B6B34,
            uint64: 0x4B_6B34_ABCC,
            float: 2.34,
            double: Double(Float.greatestFiniteMagnitude) * 2.0,
            string: "Hello",
            stringM: "こんにちは",
            map: ["17": .init(tag: "tag17"), "18": .init(tag: "tag18")],
            mapP: ["19": .init(tag: "tag19"), "20": nil],
            floatMap: [1.41: "sqrt(2)", 3.14: "pi"],
            nilArray: nil,
            emptyArray: [],
            bytes: Data([27, 28, 29]),
            superCodable: .init(name: "hello", index: 3),
            ext1: .init(a: 0x46),
            time32: MsgPackTimestamp(seconds: 1_655_888_192, nanoseconds: 0),
            time32_min: MsgPackTimestamp(seconds: 0, nanoseconds: 0),
            time64: MsgPackTimestamp(seconds: 1_655_888_192, nanoseconds: 999_999_999),
            time64_min: MsgPackTimestamp(seconds: 0, nanoseconds: 1),
            time96: MsgPackTimestamp(seconds: 9_223_372_036_854_775_807, nanoseconds: 999_999_999),
            time96_min: MsgPackTimestamp(seconds: -9_223_372_036_854_775_808, nanoseconds: 0)
        )
    }
}

class Small: Codable, Hashable {
    static func == (lhs: Small, rhs: Small) -> Bool {
        lhs.tag == rhs.tag
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(tag)
    }

    let tag: String
    init(tag: String) {
        self.tag = tag
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Self.CodingKeys.self)
        try container.encode(tag, forKey: .tag)
    }
}

class Name: Codable {
    let name: String
    init(name: String) {
        self.name = name
    }

    private enum CodingKeys: String, CodingKey {
        case name
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Self.CodingKeys.self)
        try container.encode(name, forKey: .name)
    }
}

class SuperCodable: Name {
    let index: Int

    private enum CodingKeys: String, CodingKey {
        case index
    }

    required init(name: String, index: Int) {
        self.index = index
        super.init(name: name)
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let superDecoder = try container.superDecoder(forKey: .index)
        index = try Int(from: superDecoder)
        let superDecoder2 = try container.superDecoder()
        try super.init(from: superDecoder2)
    }

    override func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let superEncoder = container.superEncoder(forKey: .index)
        try index.encode(to: superEncoder)
        let superEncoder2 = container.superEncoder()
        try super.encode(to: superEncoder2)
    }
}

extension SuperCodable: Equatable {
    static func == (lhs: SuperCodable, rhs: SuperCodable) -> Bool {
        lhs.name == rhs.name && lhs.index == rhs.index
    }
}

struct Opacity: Equatable {
    private let a: UInt8
    init(a: UInt8) {
        self.a = a
    }
}

extension Opacity: MsgPackCodable {
    var type: Int8 { 1 }
    func encodeMsgPack() throws -> [UInt8] {
        [a]
    }

    init(msgPack data: Data) throws {
        a = UInt8(bigEndian: data.withUnsafeBytes { $0.baseAddress?.assumingMemoryBound(to: UInt8.self).pointee ?? 0 })
    }
}

struct Position: MsgPackEncodable {
    private let x: UInt8
    private let y: UInt8
    init(x: UInt8, y: UInt8) {
        self.x = x
        self.y = y
    }

    func encodeMsgPack() throws -> [UInt8] {
        [x, y]
    }

    let type: Int8 = 2
}

struct SS2: MsgPackEncodable {
    private let a: String
    init(a: String) {
        self.a = a
    }

    func encodeMsgPack() throws -> [UInt8] {
        [UInt8](a.utf8)
    }

    let type: Int8 = 3
}

struct Ext16: MsgPackEncodable {
    private let a: [UInt8]
    init(a: [UInt8]) {
        self.a = a
    }

    func encodeMsgPack() throws -> [UInt8] {
        a
    }

    let type: Int8 = 5
}
