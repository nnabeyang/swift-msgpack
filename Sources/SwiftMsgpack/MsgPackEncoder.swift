import Foundation

private protocol _MsgPackDictionaryEncodableMarker {}

extension Dictionary: _MsgPackDictionaryEncodableMarker where Key: Encodable, Value: Encodable {}

open class MsgPackEncoder {
    public struct OutputOption: OptionSet, Sendable {
        public let rawValue: UInt

        public init(rawValue: UInt) {
            self.rawValue = rawValue
        }

        public static let str8FormatSupport = OutputOption(rawValue: 1 << 0)
    }

    let options: OutputOption

    public init(options: OutputOption = [.str8FormatSupport]) {
        self.options = options
    }

    open func encode<T: Encodable>(_ value: T) throws -> Data {
        let value: MsgPackEncodedValue = try encodeAsMsgPackValue(value)
        let writer = MsgPackValue.Writer()
        let bytes = writer.writeValue(value)
        return Data(bytes)
    }

    func encodeAsMsgPackValue<T: Encodable>(_ value: T) throws -> MsgPackEncodedValue {
        let encoder = _MsgPackEncoder(codingPath: [], options: options)
        guard let result = try encoder.wrapEncodable(value, for: CodingKey?.none) else {
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: [], debugDescription: "Top-level \(T.self) did not encode any values."))
        }
        return result
    }
}

indirect enum MsgPackEncodedValue {
    case none
    case literal([UInt8])
    case ext(Int8, [UInt8])
    case array([MsgPackEncodedValue])
    case map([MsgPackEncodedValue])

    static let Nil = literal([0xC0])

    var debugDataTypeDescription: String {
        switch self {
        case .none: return "nil"
        case .literal: return "literal"
        case .ext: return "ext"
        case .array: return "array"
        case .map: return "map"
        }
    }
}

extension MsgPackEncodedValue {
    func asMap() -> MsgPackEncodedValue {
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
}

public protocol MsgPackEncodable: Encodable {
    func encodeMsgPack() throws -> [UInt8]
    var type: Int8 { get }
}

private class _MsgPackEncoder: Encoder {
    public var codingPath: [CodingKey] = []
    public var userInfo: [CodingUserInfoKey: Any] = [:]
    fileprivate let options: MsgPackEncoder.OutputOption

    init(codingPath: [CodingKey] = [], options: MsgPackEncoder.OutputOption) {
        self.codingPath = codingPath
        self.options = options
    }

    var singleValue: MsgPackEncodedValue?
    var array: MsgPackFuture.RefArray?
    var map: MsgPackFuture.RefMap?
    var value: MsgPackEncodedValue? {
        if let array: MsgPackFuture.RefArray = array {
            return .array(array.values)
        }
        if let map: MsgPackFuture.RefMap = map {
            var a: [MsgPackEncodedValue] = []
            let values = map.values
            a.reserveCapacity(values.count * 2)
            for (k, v) in values {
                a.append(k)
                a.append(v)
            }
            return .map(a)
        }
        return singleValue
    }

    public func container<Key>(keyedBy _: Key.Type) -> KeyedEncodingContainer<Key> where Key: CodingKey {
        if map != nil {
            return KeyedEncodingContainer(MsgPackKeyedEncodingContainer(referencing: self, codingPath: codingPath))
        }
        map = .init()
        return KeyedEncodingContainer(MsgPackKeyedEncodingContainer(referencing: self, codingPath: codingPath))
    }

    public func unkeyedContainer() -> UnkeyedEncodingContainer {
        if array != nil {
            return MsgPackUnkeyedEncodingContainer(referencing: self, codingPath: codingPath)
        }
        array = .init()
        return MsgPackUnkeyedEncodingContainer(referencing: self, codingPath: codingPath)
    }

    public func singleValueContainer() -> SingleValueEncodingContainer {
        MsgPackSingleValueEncodingContainer(encoder: self, codingPath: codingPath)
    }
}

extension _MsgPackEncoder: _SpecialTreatmentEncoder {
    var encoder: _MsgPackEncoder {
        self
    }
}

private enum MsgPackFuture {
    case value(MsgPackEncodedValue)
    case encoder(_MsgPackEncoder)
    case nestedArray(RefArray)
    case nestedMap(RefMap)

    class RefArray {
        private(set) var array: [MsgPackFuture] = []

        init() {
            array.reserveCapacity(10)
        }

        @inline(__always)
        func append(_ element: MsgPackEncodedValue) {
            array.append(.value(element))
        }

        @inline(__always)
        func append(_ encoder: _MsgPackEncoder) {
            array.append(.encoder(encoder))
        }

        @inline(__always)
        func appendArray() -> RefArray {
            let array = RefArray()
            self.array.append(.nestedArray(array))
            return array
        }

        @inline(__always)
        func appendMap() -> RefMap {
            let map = RefMap()
            array.append(.nestedMap(map))
            return map
        }

        var values: [MsgPackEncodedValue] {
            array.compactMap { future in
                switch future {
                case let .value(value):
                    return value
                case let .nestedArray(array):
                    return .array(array.values)
                case let .nestedMap(map):
                    let values = map.values
                    let n = values.count
                    var a: [MsgPackEncodedValue] = []
                    a.reserveCapacity(n * 2)
                    for (k, v) in values {
                        a.append(k)
                        a.append(v)
                    }
                    return .map(a)
                case let .encoder(encoder):
                    return encoder.value
                }
            }
        }
    }

    class RefMap {
        private(set) var keys: [MsgPackStringKey] = []
        private(set) var dict: [String: MsgPackFuture] = [:]
        init() {
            dict.reserveCapacity(20)
        }

        @inline(__always)
        func set(_ value: MsgPackEncodedValue, for key: MsgPackStringKey) {
            if dict[key.stringValue] == nil {
                keys.append(key)
            }
            dict[key.stringValue] = .value(value)
        }

        @inline(__always)
        func setArray(for key: MsgPackStringKey) -> RefArray {
            switch dict[key.stringValue] {
            case let .nestedArray(array):
                return array
            case .value:
                let array: MsgPackFuture.RefArray = .init()
                dict[key.stringValue] = .nestedArray(array)
                return array
            case .none:
                let array: MsgPackFuture.RefArray = .init()
                dict[key.stringValue] = .nestedArray(array)
                keys.append(key)
                return array
            case .nestedMap:
                preconditionFailure("For key \"\(key)\" a keyed container has already been created.")
            case .encoder:
                preconditionFailure("For key \"\(key)\" an encoder has already been created.")
            }
        }

        @inline(__always)
        func setMap(for key: MsgPackStringKey) -> RefMap {
            switch dict[key.stringValue] {
            case let .nestedMap(map):
                return map
            case .value:
                let map: MsgPackFuture.RefMap = .init()
                dict[key.stringValue] = .nestedMap(map)
                return map
            case .none:
                let map: MsgPackFuture.RefMap = .init()
                dict[key.stringValue] = .nestedMap(map)
                keys.append(key)
                return map
            case .nestedArray:
                preconditionFailure("For key \"\(key)\" a unkeyed container has already been created.")
            case .encoder:
                preconditionFailure("For key \"\(key)\" an encoder has already been created.")
            }
        }

        @inline(__always)
        func set(_ encoder: _MsgPackEncoder, for key: MsgPackStringKey) {
            switch dict[key.stringValue] {
            case .encoder:
                preconditionFailure("For key \"\(key)\" an encoder has already been created.")
            case .nestedMap:
                preconditionFailure("For key \"\(key)\" a keyed container has already been created.")
            case .nestedArray:
                preconditionFailure("For key \"\(key)\" a unkeyed container has already been created.")
            case .value:
                dict[key.stringValue] = .encoder(encoder)
            case .none:
                dict[key.stringValue] = .encoder(encoder)
                keys.append(key)
            }
        }

        var values: [(MsgPackEncodedValue, MsgPackEncodedValue)] {
            keys.compactMap {
                switch dict[$0.stringValue] {
                case let .value(value):
                    return ($0.msgPackValue, value)
                case let .nestedArray(array):
                    return ($0.msgPackValue, .array(array.values))
                case let .nestedMap(map):
                    var a: [MsgPackEncodedValue] = []
                    let values = map.values
                    a.reserveCapacity(values.count * 2)
                    for (k, v) in map.values {
                        a.append(k)
                        a.append(v)
                    }
                    return ($0.msgPackValue, .map(a))
                case let .encoder(encoder):
                    guard let value = encoder.value else {
                        return nil
                    }
                    return ($0.msgPackValue, value)
                case .none:
                    return nil
                }
            }
        }
    }
}

private protocol _SpecialTreatmentEncoder {
    var codingPath: [CodingKey] { get }
    var encoder: _MsgPackEncoder { get }
    var options: MsgPackEncoder.OutputOption { get }
}

extension FixedWidthInteger {
    func bigEndianBytes<T: FixedWidthInteger>(as _: T.Type) -> [UInt8] {
        withUnsafeBytes(of: T(self).bigEndian) { Array($0) }
    }
}

private extension _SpecialTreatmentEncoder {
    func wrapFloat<F: FloatingPoint & DataNumber>(_ value: F, for additionalKey: CodingKey?) throws -> MsgPackEncodedValue {
        let bits = value.bytes
        if bits.count == 4 {
            return .literal([0xCA] + bits)
        }
        if bits.count == 8 {
            return .literal([0xCB] + bits)
        }
        let path: [CodingKey]
        if let additionalKey = additionalKey {
            path = codingPath + [additionalKey]
        } else {
            path = codingPath
        }
        throw EncodingError.invalidValue(value, .init(
            codingPath: path,
            debugDescription: "Unable to encode \(F.self).\(value) directly in MessagePack."
        ))
    }

    func wrapInt<T: SignedInteger & FixedWidthInteger>(_ value: T, for additionalKey: CodingKey?) throws -> MsgPackEncodedValue {
        if Int.fixMin <= value, value <= Int.fixMax {
            return .literal(value.bigEndianBytes(as: Int8.self))
        }
        if Int8.min <= value, value <= Int8.max {
            return .literal([0xD0] + value.bigEndianBytes(as: Int8.self))
        }
        if Int16.min <= value, value <= Int16.max {
            return .literal([0xD1] + value.bigEndianBytes(as: Int16.self))
        }
        if Int32.min <= value, value <= Int32.max {
            return .literal([0xD2] + value.bigEndianBytes(as: Int32.self))
        }
        if Int64.min <= value, value <= Int64.max {
            return .literal([0xD3] + value.bigEndianBytes(as: Int64.self))
        }

        let path: [CodingKey]
        if let additionalKey = additionalKey {
            path = codingPath + [additionalKey]
        } else {
            path = codingPath
        }
        throw EncodingError.invalidValue(value, .init(
            codingPath: path,
            debugDescription: "Unable to encode \(T.self).\(value) directly in MessagePack."
        ))
    }

    func wrapUInt<T: UnsignedInteger & FixedWidthInteger>(_ value: T, for additionalKey: CodingKey?) throws -> MsgPackEncodedValue {
        if value <= Int.fixMax {
            return .literal([UInt8(value)])
        }
        if value <= UInt8.max {
            return .literal([0xCC, UInt8(value)])
        }
        if value <= UInt16.max {
            return .literal([0xCD] + value.bigEndianBytes(as: UInt16.self))
        }
        if value <= UInt32.max {
            return .literal([0xCE] + value.bigEndianBytes(as: UInt32.self))
        }
        if value <= UInt64.max {
            return .literal([0xCF] + value.bigEndianBytes(as: UInt64.self))
        }

        let path: [CodingKey]
        if let additionalKey = additionalKey {
            path = codingPath + [additionalKey]
        } else {
            path = codingPath
        }
        throw EncodingError.invalidValue(value, .init(
            codingPath: path,
            debugDescription: "Unable to encode \(T.self).\(value) directly in MessagePack."
        ))
    }

    func wrapBool(_ value: Bool) -> MsgPackEncodedValue {
        .literal(value ? [0xC3] : [0xC2])
    }

    func wrapStringKey(_ value: String, for key: CodingKey?) throws -> MsgPackStringKey {
        try MsgPackStringKey(stringValue: value, msgPackValue: wrapString(value, for: key))
    }

    func wrapString(_ value: String, for additionalKey: CodingKey?) throws -> MsgPackEncodedValue {
        if let value = wrapRaw([UInt8](value.utf8)) { return value }
        let path: [CodingKey]
        if let additionalKey = additionalKey {
            path = codingPath + [additionalKey]
        } else {
            path = codingPath
        }
        throw EncodingError.invalidValue(value, .init(
            codingPath: path,
            debugDescription: "Unable to encode String.\(value) directly in MessagePack."
        ))
    }

    func wrapRaw(_ value: [UInt8]) -> MsgPackEncodedValue? {
        let n = value.count
        let bits: [UInt8]
        if n <= UInt.maxUint5 {
            bits = [UInt8(0xA0 + n)] + value
        } else if n <= UInt16.max {
            bits = if options.contains(.str8FormatSupport), n <= UInt8.max {
                [0xD9, UInt8(n)] + value
            } else {
                [0xDA] + n.bigEndianBytes(as: UInt16.self) + value
            }
        } else if n <= UInt32.max {
            bits = [0xDB] + n.bigEndianBytes(as: UInt32.self) + value
        } else {
            return nil
        }
        return .literal(bits)
    }

    func wrapEncodable<E: Encodable>(_ encodable: E, for additionalKey: CodingKey?) throws -> MsgPackEncodedValue? {
        let encoder = getEncoder(for: additionalKey)
        switch encodable {
        case let data as Data:
            return try wrapData(data, for: additionalKey)
        case let msgPack as MsgPackEncodable:
            return try wrapMsgPackEncodable(msgPack, for: additionalKey)
        default:
            try encodable.encode(to: encoder)
        }

        if let anyCodable = encodable as? AnyCodable {
            if anyCodable.base as? _MsgPackDictionaryEncodableMarker != nil {
                return encoder.value?.asMap()
            }
        } else {
            if (encodable as? _MsgPackDictionaryEncodableMarker) != nil {
                return encoder.value?.asMap()
            }
        }
        return encoder.value
    }

    func wrapData(_ data: Data, for additionalKey: CodingKey?) throws -> MsgPackEncodedValue {
        if options.contains(.str8FormatSupport) {
            let n = data.count
            if n <= UInt8.max {
                let bits = [0xC4, UInt8(n)] + [UInt8](data)
                return .literal(bits)
            } else if n <= UInt16.max {
                let bits = [0xC5] + n.bigEndianBytes(as: UInt16.self) + [UInt8](data)
                return .literal(bits)
            } else if n <= UInt32.max {
                let bits = [0xC6] + n.bigEndianBytes(as: UInt32.self) + [UInt8](data)
                return .literal(bits)
            }
        } else {
            if let value = wrapRaw([UInt8](data)) {
                return value
            }
        }
        let path: [CodingKey]
        if let additionalKey = additionalKey {
            path = codingPath + [additionalKey]
        } else {
            path = codingPath
        }
        throw EncodingError.invalidValue(data, .init(
            codingPath: path,
            debugDescription: "Unable to encode Data.\(data) directly in MessagePack."
        ))
    }

    func wrapMsgPackEncodable(_ encodable: MsgPackEncodable, for additionalKey: CodingKey?) throws -> MsgPackEncodedValue {
        var d = [UInt8]()
        let data = try encodable.encodeMsgPack()
        let n = data.count
        switch n {
        case 1:
            d.append(0xD4)
        case 2:
            d.append(0xD5)
        case 4:
            d.append(0xD6)
        case 8:
            d.append(0xD7)
        case 16:
            d.append(0xD8)
        default:
            if n <= UInt8.max {
                d.append(contentsOf: [0xC7] + n.bigEndianBytes(as: UInt8.self))
            } else if n <= UInt16.max {
                d.append(contentsOf: [0xC8] + n.bigEndianBytes(as: UInt16.self))
            } else if n <= UInt32.max {
                d.append(contentsOf: [0xC9] + n.bigEndianBytes(as: UInt32.self))
            } else {
                let path: [CodingKey]
                if let additionalKey = additionalKey {
                    path = codingPath + [additionalKey]
                } else {
                    path = codingPath
                }
                throw EncodingError.invalidValue(encodable, .init(
                    codingPath: path,
                    debugDescription: "Unable to encode \(type(of: encodable)).\(encodable) directly in MessagePack."
                ))
            }
        }
        d.append(contentsOf: encodable.type.bigEndianBytes(as: Int8.self))
        d.append(contentsOf: data)
        return .ext(encodable.type, d)
    }

    func getEncoder(for additionalKey: CodingKey?) -> _MsgPackEncoder {
        if let additionalKey = additionalKey {
            let newCodidngPath: [CodingKey] = codingPath + [additionalKey]
            return _MsgPackEncoder(codingPath: newCodidngPath, options: options)
        }
        return encoder
    }
}

private struct MsgPackSingleValueEncodingContainer: SingleValueEncodingContainer, _SpecialTreatmentEncoder {
    let encoder: _MsgPackEncoder
    let codingPath: [CodingKey]

    init(encoder: _MsgPackEncoder, codingPath: [CodingKey]) {
        self.encoder = encoder
        self.codingPath = codingPath
    }

    var options: MsgPackEncoder.OutputOption {
        encoder.options
    }

    public func encodeNil() throws {
        encoder.singleValue = .Nil
    }

    public func encode(_ value: Bool) throws {
        encoder.singleValue = encoder.wrapBool(value)
    }

    public func encode(_ value: String) throws {
        encoder.singleValue = try encoder.wrapString(value, for: nil)
    }

    public func encode(_ value: Double) throws {
        try encodeFloat(value)
    }

    public func encode(_ value: Float) throws {
        try encodeFloat(value)
    }

    public func encode(_ value: Int) throws {
        try encodeInt(value)
    }

    public func encode(_ value: Int8) throws {
        try encodeInt(value)
    }

    public func encode(_ value: Int16) throws {
        try encodeInt(value)
    }

    public func encode(_ value: Int32) throws {
        try encodeInt(value)
    }

    public func encode(_ value: Int64) throws {
        try encodeInt(value)
    }

    @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
    public func encode(_ value: Int128) throws {
        try encodeInt(value)
    }

    public func encode(_ value: UInt) throws {
        try encodeUInt(value)
    }

    public func encode(_ value: UInt8) throws {
        try encodeUInt(value)
    }

    public func encode(_ value: UInt16) throws {
        try encodeUInt(value)
    }

    public func encode(_ value: UInt32) throws {
        try encodeUInt(value)
    }

    public func encode(_ value: UInt64) throws {
        try encodeUInt(value)
    }

    @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
    public func encode(_ value: UInt128) throws {
        try encodeUInt(value)
    }

    public func encode<T>(_ value: T) throws where T: Encodable {
        encoder.singleValue = try wrapEncodable(value, for: nil)
    }

    @inline(__always)
    private func encodeInt<T: SignedInteger & FixedWidthInteger>(_ value: T) throws {
        encoder.singleValue = try encoder.wrapInt(value, for: nil)
    }

    @inline(__always)
    private func encodeUInt<T: UnsignedInteger & FixedWidthInteger>(_ value: T) throws {
        encoder.singleValue = try encoder.wrapUInt(value, for: nil)
    }

    @inline(__always)
    private func encodeFloat<T: FloatingPoint & DataNumber>(_ value: T) throws {
        encoder.singleValue = try encoder.wrapFloat(value, for: nil)
    }
}

private struct MsgPackUnkeyedEncodingContainer: UnkeyedEncodingContainer {
    private let encoder: _MsgPackEncoder
    let array: MsgPackFuture.RefArray
    private(set) var codingPath: [CodingKey]
    var count: Int {
        array.array.count
    }

    init(referencing encoder: _MsgPackEncoder, codingPath: [CodingKey]) {
        self.encoder = encoder
        array = encoder.array!
        self.codingPath = codingPath
    }

    init(referencing encoder: _MsgPackEncoder, array: MsgPackFuture.RefArray, codingPath: [CodingKey]) {
        self.encoder = encoder
        self.array = array
        self.codingPath = codingPath
    }

    func encodeNil() throws {
        array.append(.Nil)
    }

    func encode(_ value: Bool) throws {
        array.append(encoder.wrapBool(value))
    }

    func encode(_ value: String) throws {
        try array.append(encoder.wrapString(value, for: nil))
    }

    func encode(_ value: Double) throws {
        try encodeFloat(value)
    }

    func encode(_ value: Float) throws {
        try encodeFloat(value)
    }

    func encode(_ value: Int) throws {
        try encodeInt(value)
    }

    func encode(_ value: Int8) throws {
        try encodeInt(value)
    }

    func encode(_ value: Int16) throws {
        try encodeInt(value)
    }

    func encode(_ value: Int32) throws {
        try encodeInt(value)
    }

    func encode(_ value: Int64) throws {
        try encodeInt(value)
    }

    func encode(_ value: UInt) throws {
        try encodeUInt(value)
    }

    func encode(_ value: UInt8) throws {
        try encodeUInt(value)
    }

    func encode(_ value: UInt16) throws {
        try encodeUInt(value)
    }

    func encode(_ value: UInt32) throws {
        try encodeUInt(value)
    }

    func encode(_ value: UInt64) throws {
        try encodeUInt(value)
    }

    func encode<T>(_ value: T) throws where T: Encodable {
        let key: MsgPackKey = .init(index: count)
        let encoded = try encoder.wrapEncodable(value, for: key)
        array.append(encoded ?? .Nil)
    }

    private func encodeUInt<T: UnsignedInteger & FixedWidthInteger>(_ value: T) throws {
        try array.append(encoder.wrapUInt(value, for: nil))
    }

    private func encodeInt<T: SignedInteger & FixedWidthInteger>(_ value: T) throws {
        try array.append(encoder.wrapInt(value, for: nil))
    }

    private func encodeFloat<T: FloatingPoint & DataNumber>(_ value: T) throws {
        try array.append(encoder.wrapFloat(value, for: nil))
    }

    func nestedContainer<NestedKey>(keyedBy _: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> where NestedKey: CodingKey {
        let newPath = codingPath + [MsgPackKey(index: count)]
        let map = array.appendMap()
        let nestedContainer = MsgPackKeyedEncodingContainer<NestedKey>(referencing: encoder, map: map, codingPath: newPath)
        return KeyedEncodingContainer(nestedContainer)
    }

    func nestedUnkeyedContainer() -> UnkeyedEncodingContainer {
        let newPath = codingPath + [MsgPackKey(index: count)]
        let array = array.appendArray()
        let nestedContainer = MsgPackUnkeyedEncodingContainer(referencing: encoder, array: array, codingPath: newPath)
        return nestedContainer
    }

    func superEncoder() -> Encoder {
        let encoder = encoder.getEncoder(for: MsgPackKey(index: count))
        array.append(encoder)
        return encoder
    }
}

private struct MsgPackKeyedEncodingContainer<K: CodingKey>: KeyedEncodingContainerProtocol {
    typealias Key = K

    private let encoder: _MsgPackEncoder
    let map: MsgPackFuture.RefMap
    private(set) var codingPath: [CodingKey]

    init(referencing encoder: _MsgPackEncoder, codingPath: [CodingKey]) {
        self.encoder = encoder
        self.codingPath = codingPath
        map = encoder.map!
    }

    init(referencing encoder: _MsgPackEncoder, map: MsgPackFuture.RefMap, codingPath: [CodingKey]) {
        self.encoder = encoder
        self.codingPath = codingPath
        self.map = map
    }

    func encodeNil(forKey key: Key) throws {
        try map.set(.Nil, for: encoder.wrapStringKey(key.stringValue, for: key))
    }

    func encode(_ value: Bool, forKey key: Key) throws {
        let value = encoder.wrapBool(value)
        try map.set(value, for: encoder.wrapStringKey(key.stringValue, for: key))
    }

    func encode(_ value: String, forKey key: Key) throws {
        let value = try encoder.wrapString(value, for: key)
        try map.set(value, for: encoder.wrapStringKey(key.stringValue, for: key))
    }

    func encode(_ value: Double, forKey key: Key) throws {
        try encodeFloat(value, for: key)
    }

    func encode(_ value: Float, forKey key: Key) throws {
        try encodeFloat(value, for: key)
    }

    func encode(_ value: Int, forKey key: Key) throws {
        try encodeInt(value, for: key)
    }

    func encode(_ value: Int8, forKey key: Key) throws {
        try encodeInt(value, for: key)
    }

    func encode(_ value: Int16, forKey key: Key) throws {
        try encodeInt(value, for: key)
    }

    func encode(_ value: Int32, forKey key: Key) throws {
        try encodeInt(value, for: key)
    }

    func encode(_ value: Int64, forKey key: Key) throws {
        try encodeInt(value, for: key)
    }

    @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
    public func encode(_ value: Int128, forKey key: Key) throws {
        try encodeInt(value, for: key)
    }

    func encode(_ value: UInt, forKey key: Key) throws {
        try encodeUInt(value, forKey: key)
    }

    func encode(_ value: UInt8, forKey key: Key) throws {
        try encodeUInt(value, forKey: key)
    }

    func encode(_ value: UInt16, forKey key: Key) throws {
        try encodeUInt(value, forKey: key)
    }

    func encode(_ value: UInt32, forKey key: Key) throws {
        try encodeUInt(value, forKey: key)
    }

    func encode(_ value: UInt64, forKey key: Key) throws {
        try encodeUInt(value, forKey: key)
    }

    @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
    public func encode(_ value: UInt128, forKey key: Key) throws {
        try encodeUInt(value, forKey: key)
    }

    func encode<T>(_ value: T, forKey key: Key) throws where T: Encodable {
        let encoded = try encoder.wrapEncodable(value, for: key)
        try map.set(encoded ?? .Nil, for: encoder.wrapStringKey(key.stringValue, for: key))
    }

    func nestedContainer<NestedKey>(keyedBy _: NestedKey.Type, forKey key: Key) -> KeyedEncodingContainer<NestedKey> where NestedKey: CodingKey {
        let newPath = codingPath + [key]
        let map: MsgPackFuture.RefMap = map.setMap(for: try! encoder.wrapStringKey(key.stringValue, for: key))
        let nestedContainer = MsgPackKeyedEncodingContainer<NestedKey>(referencing: encoder, map: map, codingPath: newPath)
        return KeyedEncodingContainer(nestedContainer)
    }

    func nestedUnkeyedContainer(forKey key: Self.Key) -> UnkeyedEncodingContainer {
        let newPath = codingPath + [key]
        let array: MsgPackFuture.RefArray = map.setArray(for: try! encoder.wrapStringKey(key.stringValue, for: key))
        let nestedContainer = MsgPackUnkeyedEncodingContainer(referencing: encoder, array: array, codingPath: newPath)
        return nestedContainer
    }

    func superEncoder() -> Encoder {
        let newEncoder = encoder.getEncoder(for: MsgPackKey.super)
        map.set(newEncoder, for: try! encoder.wrapStringKey(MsgPackKey.super.stringValue, for: nil))
        return newEncoder
    }

    func superEncoder(forKey key: Key) -> Encoder {
        let newEncoder = encoder.getEncoder(for: key)
        map.set(newEncoder, for: try! encoder.wrapStringKey(key.stringValue, for: key))
        return newEncoder
    }

    private func encodeFloat<T: FloatingPoint & DataNumber>(_ value: T, for key: Key) throws {
        let value = try encoder.wrapFloat(value, for: nil)
        try map.set(value, for: encoder.wrapStringKey(key.stringValue, for: key))
    }

    private func encodeInt<T: SignedInteger & FixedWidthInteger>(_ value: T, for key: Key) throws {
        let value = try encoder.wrapInt(value, for: key)
        try map.set(value, for: encoder.wrapStringKey(key.stringValue, for: key))
    }

    private func encodeUInt<T: UnsignedInteger & FixedWidthInteger>(_ value: T, forKey key: Key) throws {
        let value = try encoder.wrapUInt(value, for: key)
        try map.set(value, for: encoder.wrapStringKey(key.stringValue, for: key))
    }
}

struct MsgPackKey: CodingKey {
    public var stringValue: String
    public var intValue: Int?

    public init(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    public init?(intValue: Int) {
        stringValue = intValue.description
        self.intValue = intValue
    }

    init(index: Int) {
        stringValue = "Index \(index)"
        intValue = index
    }

    static let `super`: MsgPackKey = .init(stringValue: "super")
}

private extension Int {
    static let fixMax = 0x7F
    static let fixMin = -0x20
}

extension UInt {
    static let maxUint4 = 1 << 4 - 1
    static let maxUint5 = 1 << 5 - 1
}
