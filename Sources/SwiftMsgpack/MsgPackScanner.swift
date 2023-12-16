import Foundation

enum MsgPackValueLiteralType {
    case `nil`
    case bool(Bool)
    case int(Data)
    case uint(Data)
    case float(Data)
    case str(Data)
    case bin(Data)
    var data: Data {
        switch self {
        case .nil:
            return .init([0xC0])
        case let .bool(v):
            return v ? .init([0xC3]) : .init([0xC2])
        case let .int(v):
            return v
        case let .uint(v):
            return v
        case let .float(v):
            return v
        case let .str(v):
            return v
        case let .bin(v):
            return v
        }
    }
}

extension MsgPackValueLiteralType {
    var debugDataTypeDescription: String {
        switch self {
        case .nil:
            return "nil"
        case .bool:
            return "bool"
        case .int:
            return "int"
        case .uint:
            return "uint"
        case .float:
            return "float"
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
        case let (.int(l), .int(r)):
            return l == r
        case let (.uint(l), .uint(r)):
            return l == r
        case let (.float(l), .float(r)):
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
        case let .int(v):
            hasher.combine(0x3)
            hasher.combine(v)
        case let .uint(v):
            hasher.combine(0x4)
            hasher.combine(v)
        case let .float(v):
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

indirect enum MsgPackValue {
    case none
    case literal(MsgPackValueLiteralType)
    case ext(Int8, Data)
    case array([MsgPackValue])
    case map([MsgPackValue])
    static let Nil = literal(.nil)
}

extension MsgPackValue {
    var count: Int {
        switch self {
        case .none:
            return 0
        case .literal:
            return 1
        case .ext:
            return 1
        case let .array(a):
            return a.count
        case let .map(a):
            return a.count / 2
        }
    }

    func asArray() -> MsgPackValue {
        switch self {
        case .none:
            return .array([])
        case .literal:
            return .array([self])
        case .ext:
            return .array([self])
        case .array:
            return self
        case let .map(a):
            return .array(a)
        }
    }

    func asMap() -> MsgPackValue {
        switch self {
        case .none, .literal, .ext:
            return .map([])
        case let .array(a):
            if a.count % 2 != 0 {
                return .map([])
            }
            return .map(a)
        case .map:
            return self
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

    subscript(index: Int) -> MsgPackValue {
        switch self {
        case .none, .literal, .ext:
            return .none
        case let .array(a):
            return a[index]
        case let .map(a):
            return a[index * 2 + 1]
        }
    }

    var keys: [Dictionary<MsgPackValue, MsgPackValue>.Key] {
        if case let .map(a) = self {
            var aa = [Dictionary<MsgPackValue, MsgPackValue>.Key]()
            for i in 0 ..< a.count where i % 2 == 0 {
                aa.append(a[i])
            }
            return aa
        } else {
            return []
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
        func writeValue(_ value: MsgPackValue) -> [UInt8] {
            var bytes: [UInt8] = .init()
            writeValue(value, into: &bytes)
            return bytes
        }

        private func writeValue(_ value: MsgPackValue, into bytes: inout [UInt8]) {
            switch value {
            case let .literal(v):
                let data = v.data
                let bs: [UInt8] = data.withUnsafeBytes { (pointer: UnsafeRawBufferPointer) -> [UInt8] in
                    let unsafeBufferPointer = pointer.bindMemory(to: UInt8.self)
                    let unsafePointer = unsafeBufferPointer.baseAddress!
                    return [UInt8](UnsafeBufferPointer(start: unsafePointer, count: data.count))
                }
                bytes.append(contentsOf: bs)
            case let .ext(_, data):
                let bs: [UInt8] = data.withUnsafeBytes { (pointer: UnsafeRawBufferPointer) -> [UInt8] in
                    let unsafeBufferPointer = pointer.bindMemory(to: UInt8.self)
                    let unsafePointer = unsafeBufferPointer.baseAddress!
                    return [UInt8](UnsafeBufferPointer(start: unsafePointer, count: data.count))
                }
                bytes.append(contentsOf: bs)
            case let .array(array):
                let n = array.count
                if n <= UInt.maxUint4 {
                    bytes.append(contentsOf: [UInt8(0x90 + n)])
                } else if n <= UInt16.max {
                    var bb: [UInt8] = []
                    bb.append(0xDC)
                    let bits = withUnsafePointer(to: UInt16(n).bigEndian) {
                        Data(buffer: UnsafeBufferPointer(start: $0, count: 1))
                    }
                    bb.append(contentsOf: bits)
                    bytes.append(contentsOf: bb)
                } else {
                    var bb: [UInt8] = []
                    bb.append(0xDD)
                    let bits = withUnsafePointer(to: UInt32(n).bigEndian) {
                        Data(buffer: UnsafeBufferPointer(start: $0, count: 1))
                    }
                    bb.append(contentsOf: bits)
                    bytes.append(contentsOf: bb)
                }
                for item in array {
                    writeValue(item, into: &bytes)
                }
            case let .map(a):
                let n = a.count / 2
                if n <= UInt.maxUint4 {
                    bytes.append(contentsOf: [UInt8(0x80 + n)])
                } else if n <= UInt16.max {
                    var bb: [UInt8] = []
                    bb.append(0xDE)
                    let bits = withUnsafePointer(to: UInt16(n).bigEndian) {
                        Data(buffer: UnsafeBufferPointer(start: $0, count: 1))
                    }
                    bb.append(contentsOf: bits)
                    bytes.append(contentsOf: bb)
                } else {
                    var bb: [UInt8] = []
                    bb.append(0xDF)
                    let bits = withUnsafePointer(to: UInt32(n).bigEndian) {
                        Data(buffer: UnsafeBufferPointer(start: $0, count: 1))
                    }
                    bb.append(contentsOf: bits)
                    bytes.append(contentsOf: bb)
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
        let start = off
        try skipLiteral()
        let item = data[start ..< off]
        let c = item[start]
        switch c {
        case 0xC0: // nil
            return .literal(.nil)
        case 0xC2: // false
            return .literal(.bool(false))
        case 0xC3: // true
            return .literal(.bool(true))
        case 0xC4, 0xC5, 0xC6: // bin8, bin16, bin32
            return .literal(.bin(item.dropFirst(1 + (1 << (c - 0xC4)))))
        case 0xC7, 0xC8, 0xC9: // ext 8, ext 16, ext 32
            let nn = 1 + 1 << (c - 0xC7)
            let dd = [UInt8](item)
            let n = dd.count
            let typeNo = Int8(bigEndian: Data([dd[nn]]).withUnsafeBytes { $0.baseAddress?.assumingMemoryBound(to: Int8.self).pointee ?? 0 })
            return .ext(typeNo, .init(dd[nn + 1 ..< n]))
        case 0xCA, 0xCB: // float 32, float 64
            return .literal(.float(item.dropFirst(1)))
        case 0xCC, 0xCD, 0xCE, 0xCF: // uint8, uint16, uint32, uint64
            return .literal(.uint(item.dropFirst(1)))
        case 0xD0, 0xD1, 0xD2, 0xD3: // int8, int16, int32, int64
            return .literal(.int(item.dropFirst(1)))
        case 0xD4, 0xD5, 0xD6, 0xD7, 0xD8: // fixext 1, fixext 2, fixext 4, fixext 8
            let dd = [UInt8](item)
            let n = dd.count
            let typeNo = Int8(bigEndian: Data([dd[1]]).withUnsafeBytes { $0.baseAddress?.assumingMemoryBound(to: Int8.self).pointee ?? 0 })
            return .ext(typeNo, .init(dd[2 ..< n]))
        case 0xD9, 0xDA, 0xDB: // str8, str16, str32
            return .literal(.str(item.dropFirst(1 + (1 << (c - 0xD9)))))
        default:
            if item.count == 1, c & 0xE0 == 0xE0 { // negative fixint
                return .literal(.int(item))
            }
            if c & 0xA0 == 0xA0 { // fixstr
                return .literal(.str(item.dropFirst(1)))
            }
            if item.count == 1, c & 0x80 == 0 { // fixint
                return .literal(.uint(item))
            }
        }
        return .none
    }

    private func skipLiteral() throws {
        var i = off
        let c = data[i]
        switch c {
        case 0xC0, 0xC2, 0xC3: // nil, false, true
            break
        case 0xC4: // bin 8
            i += Int(bigEndianFixedWidthInt(data[i + 1 ..< i + 2], as: UInt8.self)) + 1
        case 0xC5: // bin 16
            i += Int(bigEndianFixedWidthInt(data[i + 1 ..< i + 3], as: UInt16.self)) + 2
        case 0xC6: // bin 32
            i += Int(bigEndianFixedWidthInt(data[i + 1 ..< i + 5], as: UInt32.self)) + 4
        case 0xC7: // ext 8
            i += Int(bigEndianFixedWidthInt(data[i + 1 ..< i + 2], as: UInt8.self)) + 2
        case 0xC8: // ext 16
            i += Int(bigEndianFixedWidthInt(data[i + 1 ..< i + 3], as: UInt16.self)) + 3
        case 0xC9: // ext 32
            i += Int(bigEndianFixedWidthInt(data[i + 1 ..< i + 5], as: UInt32.self)) + 5
        case 0xCA, 0xCB: // Float, Double
            i += 4 << (c - 0xCA)
        case 0xCC, 0xCD, 0xCE, 0xCF: // uint8, uint16, uint32, uint64
            i += 1 << (c - 0xCC)
        case 0xD0, 0xD1, 0xD2, 0xD3: // int8, int16, int32, int64
            i += 1 << (c - 0xD0)
        case 0xD4, 0xD5, 0xD6, 0xD7, 0xD8: // fixext 1, fixext 4, fixext 8, fixext 16
            i += 1 + (1 << (c - 0xD4))
        case 0xD9: // str8
            i += Int(bigEndianFixedWidthInt(data[i + 1 ..< i + 2], as: UInt8.self)) + 1
        case 0xDA: // str16
            i += Int(bigEndianFixedWidthInt(data[i + 1 ..< i + 3], as: UInt16.self)) + 2
        case 0xDB: // str32
            i += Int(bigEndianFixedWidthInt(data[i + 1 ..< i + 5], as: UInt32.self)) + 4
        default:
            if c & 0xE0 == 0xE0 { // negative fixint
                break
            }
            if c & 0xA0 == 0xA0 { // fixstr
                i += Int(c - 0xA0)
            }
        }
        off = i + 1
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

    private func readIndex() -> Int {
        off - 1
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
