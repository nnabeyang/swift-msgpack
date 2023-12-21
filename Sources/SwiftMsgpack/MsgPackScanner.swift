import Foundation

enum MsgPackValueLiteralType {
    case `nil`
    case bool(Bool)
    case int8(Data)
    case int16(Data)
    case int32(Data)
    case int64(Data)
    case uint8(Data)
    case uint16(Data)
    case uint32(Data)
    case uint64(Data)
    case float32(Data)
    case float64(Data)
    case str(Data)
    case bin(Data)
}

extension MsgPackValueLiteralType {
    var debugDataTypeDescription: String {
        switch self {
        case .nil:
            return "nil"
        case .bool:
            return "bool"
        case .int8:
            return "int8"
        case .int16:
            return "int16"
        case .int32:
            return "int32"
        case .int64:
            return "int64"
        case .uint8:
            return "uint8"
        case .uint16:
            return "uint16"
        case .uint32:
            return "uint32"
        case .uint64:
            return "uint64"
        case .float32:
            return "float32"
        case .float64:
            return "float64"
        case .str:
            return "str"
        case .bin:
            return "bin"
        }
    }
}

extension MsgPackValueLiteralType: Hashable {
    static func == (lhs: MsgPackValueLiteralType, rhs: MsgPackValueLiteralType) -> Bool {
        switch (lhs, rhs) {
        case (.nil, .nil):
            return true
        case let (.bool(l), .bool(r)):
            return l == r
        case let (.int8(l), .int8(r)):
            return l == r
        case let (.int16(l), .int16(r)):
            return l == r
        case let (.int32(l), .int32(r)):
            return l == r
        case let (.int64(l), .int64(r)):
            return l == r
        case let (.uint8(l), .uint8(r)):
            return l == r
        case let (.uint16(l), .uint16(r)):
            return l == r
        case let (.uint32(l), .uint32(r)):
            return l == r
        case let (.uint64(l), .uint64(r)):
            return l == r
        case let (.float32(l), .float32(r)):
            return l == r
        case let (.float64(l), .float64(r)):
            return l == r
        case let (.str(l), .str(r)):
            return l == r
        case let (.bin(l), .bin(r)):
            return l == r
        default:
            return false
        }
    }

    func hash(into hasher: inout Hasher) {
        switch self {
        case .nil:
            hasher.combine(0x1)
        case let .bool(v):
            hasher.combine(0x2)
            hasher.combine(v)
        case let .int8(v):
            hasher.combine(0x3)
            hasher.combine(v)
        case let .int16(v):
            hasher.combine(0x3)
            hasher.combine(v)
        case let .int32(v):
            hasher.combine(0x3)
            hasher.combine(v)
        case let .int64(v):
            hasher.combine(0x3)
            hasher.combine(v)
        case let .uint8(v):
            hasher.combine(0x4)
            hasher.combine(v)
        case let .uint16(v):
            hasher.combine(0x4)
            hasher.combine(v)
        case let .uint32(v):
            hasher.combine(0x4)
            hasher.combine(v)
        case let .uint64(v):
            hasher.combine(0x4)
            hasher.combine(v)
        case let .float32(v):
            hasher.combine(0x5)
            hasher.combine(v)
        case let .float64(v):
            hasher.combine(0x5)
            hasher.combine(v)
        case let .str(v):
            hasher.combine(0x6)
            hasher.combine(v)
        case let .bin(v):
            hasher.combine(0x7)
            hasher.combine(v)
        }
    }
}

struct MsgPackStringKey {
    let stringValue: String
    let msgPackValue: MsgPackEncodedValue
}

indirect enum MsgPackValue {
    case none
    case literal(MsgPackValueLiteralType)
    case ext(Int8, Data)
    case array([MsgPackValue])
    case map([MsgPackValue])
    static let Nil = literal(.nil)
}

extension MsgPackValue {
    func asArray() -> [MsgPackValue] {
        switch self {
        case .none:
            return []
        case .literal, .ext:
            return [self]
        case let .array(a), let .map(a):
            return a
        }
    }

    func asDictionary() -> [MsgPackValue: MsgPackValue] {
        switch self {
        case .none, .literal, .ext:
            return [:]
        case let .array(a):
            if a.count % 2 != 0 {
                return [:]
            }
            let n = a.count / 2
            var d = [MsgPackValue: MsgPackValue]()
            for i in 0 ..< n {
                let key = a[i * 2]
                let value = a[i * 2 + 1]
                d[key] = value
            }
            return d
        case let .map(a):
            let n = a.count / 2
            var d = [MsgPackValue: MsgPackValue]()
            for i in 0 ..< n {
                let key = a[i * 2]
                let value = a[i * 2 + 1]
                d[key] = value
            }
            return d
        }
    }
}

extension MsgPackValue: ExpressibleByStringLiteral {
    init(stringLiteral value: String) {
        self = .literal(.str(Data(value.utf8)))
    }
}

extension MsgPackValue {
    var debugDataTypeDescription: String {
        switch self {
        case .none:
            return "none"
        case let .literal(v):
            return v.debugDataTypeDescription
        case .ext:
            return "a extension"
        case .array:
            return "an array"
        case .map:
            return "a map"
        }
    }
}

extension MsgPackValue: Hashable {
    static func == (lhs: MsgPackValue, rhs: MsgPackValue) -> Bool {
        switch (lhs, rhs) {
        case let (.literal(l), .literal(r)):
            return l == r
        case let (.ext(ln, l), .ext(rn, r)):
            return ln == rn && l == r
        case let (.array(l), .array(r)):
            return l == r
        case let (.map(l), .map(r)):
            return l == r
        default:
            return false
        }
    }

    func hash(into hasher: inout Hasher) {
        switch self {
        case let .literal(data):
            hasher.combine(0x1)
            hasher.combine(data)
        case let .array(array):
            hasher.combine(0x2)
            hasher.combine(array)
        case let .map(map):
            hasher.combine(0x3)
            hasher.combine(map)
        case let .ext(typeNo, data):
            hasher.combine(0x4)
            hasher.combine(typeNo)
            hasher.combine(data)
        case .none:
            break
        }
    }
}

extension MsgPackValue {
    struct Writer {
        func writeValue(_ value: MsgPackEncodedValue) -> [UInt8] {
            var bytes: [UInt8] = .init()
            writeValue(value, into: &bytes)
            return bytes
        }

        private func writeValue(_ value: MsgPackEncodedValue, into bytes: inout [UInt8]) {
            switch value {
            case let .literal(data):
                bytes.append(contentsOf: data)
            case let .ext(_, data):
                bytes.append(contentsOf: data)
            case let .array(array):
                let n = array.count
                if n <= UInt.maxUint4 {
                    bytes.append(contentsOf: [UInt8(0x90 + n)])
                } else if n <= UInt16.max {
                    bytes.append(contentsOf: [0xDC] + n.bigEndianBytes(as: UInt16.self))
                } else {
                    bytes.append(contentsOf: [0xDD] + n.bigEndianBytes(as: UInt32.self))
                }
                for item in array {
                    writeValue(item, into: &bytes)
                }
            case let .map(a):
                let n = a.count / 2
                if n <= UInt.maxUint4 {
                    bytes.append(contentsOf: [UInt8(0x80 + n)])
                } else if n <= UInt16.max {
                    bytes.append(contentsOf: [0xDE] + n.bigEndianBytes(as: UInt16.self))
                } else {
                    bytes.append(contentsOf: [0xDF] + n.bigEndianBytes(as: UInt32.self))
                }

                for i in 0 ..< n {
                    let key = a[i * 2]
                    let value = a[i * 2 + 1]
                    writeValue(key, into: &bytes)
                    writeValue(value, into: &bytes)
                }
            default:
                bytes.append(contentsOf: [])
            }
        }
    }
}

enum MsgPackOpCode {
    case literal
    case array
    case map
    case neverUsed
    case end

    init(ch c: UInt8) {
        if c <= 0xBF || c >= 0xE0 {
            if c & 0xE0 == 0xE0 { // negative fixint
                self = .literal
            } else if c & 0xA0 == 0xA0 { // fixstr
                self = .literal
            } else if c & 0x90 == 0x90 { // fixarray
                self = .array
            } else if c & 0x80 == 0x80 { // fixmap
                self = .map
            } else if c & 0x80 == 0 { // positive fixint
                self = .literal
            } else {
                self = .neverUsed
            }
        } else {
            switch c {
            case 0xC1: // never used
                self = .neverUsed
            case 0xDC, 0xDD: // array 16, array 32
                self = .array
            case 0xDE, 0xDF: // map 16, map 32
                self = .map
            default:
                self = .literal
            }
        }
    }
}

class MsgPackScanner {
    private let data: Data
    private var off = 0
    init(data: Data) {
        self.data = data
        off = 0
    }

    func scan() throws -> MsgPackValue {
        let opcode = peekOpCode()
        switch opcode {
        case .end, .neverUsed:
            return .none
        case .literal:
            return try scanLiteral()
        case .array:
            return try scanArray()
        case .map:
            return try scanMap()
        }
    }

    private func scanLiteral() throws -> MsgPackValue {
        let c = data[off]
        switch c {
        case 0xC0: // nil
            off += 1
            return .literal(.nil)
        case 0xC2: // false
            off += 1
            return .literal(.bool(false))
        case 0xC3: // true
            off += 1
            return .literal(.bool(true))
        case 0xC4: // bin8
            let n = Int(data[off + 1])
            let s = off + 1 + (1 << 0)
            let e = s + n
            off = e
            return .literal(.bin(data[s ..< e]))
        case 0xC5: // bin16
            let d = 1 << 1
            let n = Int(bigEndianFixedWidthInt(data[off + 1 ..< off + 1 + d], as: UInt16.self))
            let s = off + 1 + d
            let e = s + n
            off = e
            return .literal(.bin(data[s ..< e]))
        case 0xC6: // bin32
            let d = 1 << 2
            let n = Int(bigEndianFixedWidthInt(data[off + 1 ..< off + 1 + d], as: UInt32.self))
            let s = off + 1 + d
            let e = s + n
            off = e
            return .literal(.bin(data[s ..< e]))
        case 0xC7: // ext8
            let n = Int(data[off + 1])
            let typeNo = Int8(truncatingIfNeeded: data[off + 2])

            let s = off + 1 + (1 << 0) + 1
            let e = s + n
            off = e
            return .ext(typeNo, data[s ..< e])
        case 0xC8: // ext16
            let d = 1 << 1
            let n = Int(bigEndianFixedWidthInt(data[off + 1 ..< off + 1 + d], as: UInt16.self))
            let typeNo = Int8(truncatingIfNeeded: data[off + 2])

            let s = off + 1 + d + 1
            let e = s + n
            off = e
            return .ext(typeNo, data[s ..< e])
        case 0xC9: // ext32
            let d = 1 << 2
            let n = Int(bigEndianFixedWidthInt(data[off + 1 ..< off + 1 + d], as: UInt32.self))
            let typeNo = Int8(truncatingIfNeeded: data[off + 2])

            let s = off + 1 + d + 1
            let e = s + n
            off = e
            return .ext(typeNo, data[s ..< e])
        case 0xCA: // float32
            let s = off + 1
            let e = s + 1 << 2
            off = e
            return .literal(.float32(data[s ..< e]))
        case 0xCB: // float64
            let s = off + 1
            let e = s + 1 << 3
            off = e
            return .literal(.float64(data[s ..< e]))
        case 0xCC: // uint8
            let s = off + 1
            let e = s + 1 << 0
            off = e
            return .literal(.uint8(data[s ..< e]))
        case 0xCD: // uint16
            let s = off + 1
            let e = s + 1 << 1
            off = e
            return .literal(.uint16(data[s ..< e]))
        case 0xCE: // uint32
            let s = off + 1
            let e = s + 1 << 2
            off = e
            return .literal(.uint32(data[s ..< e]))
        case 0xCF: // uint64
            let s = off + 1
            let e = s + 1 << 3
            off = e
            return .literal(.uint64(data[s ..< e]))
        case 0xD0: // int8
            let s = off + 1
            let e = s + 1 << 0
            off = e
            return .literal(.int8(data[s ..< e]))
        case 0xD1: // int16
            let s = off + 1
            let e = s + 1 << 1
            off = e
            return .literal(.int16(data[s ..< e]))
        case 0xD2: // int32
            let s = off + 1
            let e = s + 1 << 2
            off = e
            return .literal(.int32(data[s ..< e]))
        case 0xD3: // int64
            let s = off + 1
            let e = s + 1 << 3
            off = e
            return .literal(.int64(data[s ..< e]))
        case 0xD4: // fixext1
            let typeNo = Int8(truncatingIfNeeded: data[off + 1])

            let s = off + 1 + 1
            let e = s + 1 << 0
            off = e
            return .ext(typeNo, data[s ..< e])
        case 0xD5: // fixext2
            let typeNo = Int8(truncatingIfNeeded: data[off + 1])

            let s = off + 1 + 1
            let e = s + 1 << 1
            off = e
            return .ext(typeNo, data[s ..< e])
        case 0xD6: // fixext4
            let typeNo = Int8(truncatingIfNeeded: data[off + 1])

            let s = off + 1 + 1
            let e = s + 1 << 2
            off = e
            return .ext(typeNo, data[s ..< e])
        case 0xD7: // fixext8
            let typeNo = Int8(truncatingIfNeeded: data[off + 1])

            let s = off + 1 + 1
            let e = s + 1 << 3
            off = e
            return .ext(typeNo, data[s ..< e])
        case 0xD8: // fixext16
            let typeNo = Int8(truncatingIfNeeded: data[off + 1])

            let s = off + 1 + 1
            let e = s + 1 << 4
            off = e
            return .ext(typeNo, data[s ..< e])
        case 0xD9: // str8
            let n = Int(data[off + 1])
            let s = off + 1 + (1 << 0)
            let e = s + n
            off = e
            return .literal(.str(data[s ..< e]))
        case 0xDA: // str16
            let d = 1 << 1
            let n = Int(bigEndianFixedWidthInt(data[off + 1 ..< off + 1 + d], as: UInt16.self))
            let s = off + 1 + d
            let e = s + n
            off = e
            return .literal(.str(data[s ..< e]))
        case 0xDB: // str32
            let d = 1 << 2
            let n = Int(bigEndianFixedWidthInt(data[off + 1 ..< off + 1 + d], as: UInt32.self))
            let s = off + 1 + d
            let e = s + n
            off = e
            return .literal(.str(data[s ..< e]))
        default:
            if c & 0xE0 == 0xE0 { // negative fixint
                off += 1
                return .literal(.int8(.init([c])))
            }
            if c & 0xA0 == 0xA0 { // fixstr
                let s = off + 1
                let e = s + Int(c - 0xA0)
                off = e
                return .literal(.str(data[s ..< e]))
            }
            if c & 0x80 == 0 { // fixint
                off += 1
                return .literal(.uint8(.init([c])))
            }
        }
        return .none
    }

    private func scanArray() throws -> MsgPackValue {
        let c = data[off]
        let n: Int = { () -> Int in
            switch c {
            case 0xDC: // array 16
                let dd = self.data[self.off + 1 ..< self.off + 3]
                self.off += 3
                return Int(bigEndianFixedWidthInt(dd, as: UInt16.self))
            case 0xDD: // array 32
                let dd = self.data[self.off + 1 ..< self.off + 5]
                self.off += 5
                return Int(bigEndianFixedWidthInt(dd, as: UInt32.self))
            default:
                self.off += 1
                if c & 0x90 == 0x90 {
                    return Int(c - 0x90)
                }
                return 0
            }
        }()
        var a: [MsgPackValue] = []
        for _ in 0 ..< n {
            a.append(try scan())
        }
        return .array(a)
    }

    private func scanMap() throws -> MsgPackValue {
        let c = data[off]
        let n: Int = { () -> Int in
            switch c {
            case 0xDE: // map 16
                let dd = self.data[self.off + 1 ..< self.off + 3]
                self.off += 3
                return Int(bigEndianFixedWidthInt(dd, as: UInt16.self))
            case 0xDF: // map 32
                let dd = self.data[self.off + 1 ..< self.off + 5]
                self.off += 5
                return Int(bigEndianFixedWidthInt(dd, as: UInt32.self))
            default:
                self.off += 1
                if c & 0x80 == 0x80 { // fixmap
                    return Int(c - 0x80)
                }
                return 0
            }
        }()
        var a: [MsgPackValue] = []
        for _ in 0 ..< n {
            let key = try scan()
            let val = try scan()
            a.append(key)
            a.append(val)
        }
        return .map(a)
    }

    private func peekOpCode() -> MsgPackOpCode {
        if off < data.count {
            return MsgPackOpCode(ch: data[off])
        } else {
            return .end
        }
    }
}

private extension Data {
    var hexDescription: String {
        reduce("") { $0 + String(format: "%02x", $1) }
    }
}
