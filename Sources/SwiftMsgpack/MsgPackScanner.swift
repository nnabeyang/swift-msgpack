import Foundation

enum MsgPackValueLiteralType {
    case `nil`
    case bool(Bool)
    case int(any FixedWidthInteger)
    case uint(any FixedWidthInteger)
    case float32(Float)
    case float64(Double)
    case str(UnsafeBufferPointer<UInt8>)
    case bin(Data)
}

extension MsgPackValueLiteralType {
    var debugDataTypeDescription: String {
        switch self {
        case .nil:
            return "nil"
        case .bool:
            return "bool"
        case let .int(v):
            return "\(type(of: v))"
        case let .uint(v):
            return "\(type(of: v))"
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

    func asDictionary() -> [(MsgPackValue, MsgPackValue)] {
        switch self {
        case .none, .literal, .ext:
            return []
        case let .array(a):
            if a.count % 2 != 0 {
                return []
            }
            let n = a.count / 2
            var d = [(MsgPackValue, MsgPackValue)]()
            d.reserveCapacity(n * 2)
            for i in 0 ..< n {
                let key = a[i * 2]
                let value = a[i * 2 + 1]
                d.append((key, value))
            }
            return d
        case let .map(a):
            let n = a.count / 2
            var d = [(MsgPackValue, MsgPackValue)]()
            d.reserveCapacity(n * 2)
            for i in 0 ..< n {
                let key = a[i * 2]
                let value = a[i * 2 + 1]
                d.append((key, value))
            }
            return d
        }
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
    case uint(UInt8)
    case int(UInt8)
    case str(UInt8)
    case bin(UInt8)
    case array(UInt8)
    case map(UInt8)
    case ext(UInt8)
    case simple(UInt8)
    case neverUsed
    case end

    init(ch c: UInt8) {
        if c <= 0xBF || c >= 0xE0 {
            if c & 0xE0 == 0xE0 {
                self = .int(c)
            } else if c & 0xA0 == 0xA0 {
                self = .str(c - 0xA0)
            } else if c & 0x90 == 0x90 {
                self = .array(c - 0x90)
            } else if c & 0x80 == 0x80 {
                self = .map(c - 0x80)
            } else if c & 0x80 == 0 {
                self = .uint(c)
            } else {
                self = .neverUsed
            }
        } else {
            switch c {
            case 0xC1:
                self = .neverUsed
            case 0xC4 ... 0xC6:
                self = .bin(c - 0x44)
            case 0xDC, 0xDD:
                self = .array(c - 0x5B)
            case 0xDE, 0xDF:
                self = .map(c - 0x5D)
            case 0xC7 ... 0xC9:
                self = .ext(c - 0x47)
            case 0xCC ... 0xCF:
                self = .uint(c - 0x4C)
            case 0xD0 ... 0xD3:
                self = .int(c - 0x50)
            case 0xD9 ... 0xDB:
                self = .str(c - 0x59)
            case 0xD4 ... 0xD8:
                self = .ext(1 << (c - 0xD4))
            default:
                self = .simple(c)
            }
        }
    }
}

class MsgPackScanner {
    private let start: UnsafeRawPointer
    private var ptr: UnsafeRawPointer
    private let count: Int

    init(ptr: UnsafeRawPointer, count: Int) {
        start = ptr
        self.ptr = ptr
        self.count = count
    }

    private func advanced(by n: Int) {
        ptr = ptr.advanced(by: n)
    }

    private var isAtEnd: Bool {
        start.distance(to: ptr) >= count
    }

    private func readUInt8() -> UInt8 {
        defer {
            advanced(by: 1)
        }
        return ptr.load(as: UInt8.self)
    }

    private func readInt8() -> Int8 {
        defer {
            advanced(by: 1)
        }
        return ptr.load(as: Int8.self)
    }

    private func readUnaligned<T>(as: T.Type) -> T {
        defer {
            advanced(by: MemoryLayout<T>.size)
        }
        return ptr.loadUnaligned(as: T.self)
    }

    private func readBuffer(_ n: Int) -> UnsafeBufferPointer<UInt8> {
        defer {
            advanced(by: n)
        }
        return ptr.withMemoryRebound(to: UInt8.self, capacity: n) {
            UnsafeBufferPointer<UInt8>(start: $0, count: n)
        }
    }

    func scan() -> MsgPackValue {
        switch readOpCode() {
        case .end, .neverUsed:
            .none
        case let .uint(c):
            scanUInt(c)
        case let .int(c):
            scanInt(c)
        case let .str(c):
            scanString(c)
        case let .bin(c):
            scanBinary(c)
        case let .ext(c):
            scanExtension(c)
        case let .array(c):
            scanArray(c)
        case let .map(c):
            scanMap(c)
        case let .simple(c):
            scanSimple(c)
        }
    }

    private func scanUInt(_ c: UInt8) -> MsgPackValue {
        .literal(.uint(_scanUInt(c)))
    }

    private func _scanUInt(_ c: UInt8) -> any FixedWidthInteger {
        switch c {
        case 0x80:
            readUInt8()
        case 0x81:
            readUnaligned(as: UInt16.self).bigEndian
        case 0x82:
            readUnaligned(as: UInt32.self).bigEndian
        case 0x83:
            readUnaligned(as: UInt64.self).bigEndian
        default:
            c
        }
    }

    private func getLength(_ c: UInt8) -> Int {
        let v = _scanUInt(c)
        return Int(truncatingIfNeeded: v)
    }

    private func scanInt(_ c: UInt8) -> MsgPackValue {
        switch c {
        case 0x80:
            .literal(.int(readInt8()))
        case 0x81:
            .literal(.int(readUnaligned(as: Int16.self).bigEndian))
        case 0x82:
            .literal(.int(readUnaligned(as: Int32.self).bigEndian))
        case 0x83:
            .literal(.int(readUnaligned(as: Int64.self).bigEndian))
        default:
            .literal(.int(Int8(bitPattern: c)))
        }
    }

    private func scanString(_ c: UInt8) -> MsgPackValue {
        .literal(.str(readBuffer(getLength(c))))
    }

    private func scanBinary(_ c: UInt8) -> MsgPackValue {
        .literal(.bin(.init(buffer: readBuffer(getLength(c)))))
    }

    private func scanExtension(_ c: UInt8) -> MsgPackValue {
        let n = getLength(c)
        let typeNo = Int8(bitPattern: readUInt8())
        return .ext(typeNo, .init(buffer: readBuffer(n)))
    }

    private func scanSimple(_ c: UInt8) -> MsgPackValue {
        switch c {
        case 0xC0:
            .literal(.nil)
        case 0xC2:
            .literal(.bool(false))
        case 0xC3:
            .literal(.bool(true))
        case 0xCA:
            .literal(.float32(.init(bitPattern: readUnaligned(as: UInt32.self).bigEndian)))
        case 0xCB:
            .literal(.float64(.init(bitPattern: readUnaligned(as: UInt64.self).bigEndian)))
        default:
            .none
        }
    }

    private func scanArray(_ c: UInt8) -> MsgPackValue {
        let n = getLength(c)
        var a: [MsgPackValue] = []
        a.reserveCapacity(n)
        var i = 0
        for _ in 0 ..< n {
            a.append(scan())
            i += 1
        }
        return .array(a)
    }

    private func scanMap(_ c: UInt8) -> MsgPackValue {
        let n = getLength(c)
        var a: [MsgPackValue] = []
        a.reserveCapacity(n * 2)
        for _ in 0 ..< n {
            a.append(scan())
            a.append(scan())
        }
        return .map(a)
    }

    private func readOpCode() -> MsgPackOpCode {
        !isAtEnd ? MsgPackOpCode(ch: readUInt8()) : .end
    }
}
