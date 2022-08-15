import Foundation

private protocol _MsgPackDictionaryEncodableMarker {}

extension Dictionary: _MsgPackDictionaryEncodableMarker where Key: Encodable, Value: Encodable {}

open class MsgPackEncoder {
    public init() {}
    open func encode<T: Encodable>(_ value: T) throws -> Data {
        let value: MsgPackValue = try encodeAsMsgPackValue(value)
        let writer = MsgPackValue.Writer()
        let bytes = writer.writeValue(value)
        return Data(bytes)
    }

    func encodeAsMsgPackValue<T: Encodable>(_ value: T) throws -> MsgPackValue {
        let encoder = _MsgPackEncoder(codingPath: [])
        guard let result = try encoder.wrapEncodable(value, for: CodingKey?.none) else {
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: [], debugDescription: "Top-level \(T.self) did not encode any values."))
        }
        return result
    }
}

public protocol MsgPackEncodable: Encodable {
    func encodeMsgPack() throws -> Data
    var type: Int8 { get }
}

private class _MsgPackEncoder: Encoder {
    public var codingPath: [CodingKey] = []
    public var userInfo: [CodingUserInfoKey: Any] = [:]

    init(codingPath: [CodingKey] = []) {
        self.codingPath = codingPath
    }

    var singleValue: MsgPackValue?
    var array: MsgPackFuture.RefArray?
    var map: MsgPackFuture.RefMap?
    var value: MsgPackValue? {
        if let array: MsgPackFuture.RefArray = array {
            return .array(array.values)
        }
        if let map: MsgPackFuture.RefMap = map {
            var keys: [MsgPackValue] = []
            var dict: [MsgPackValue: MsgPackValue] = [:]
            for (k, v) in map.values {
                keys.append(k)
                dict[k] = v
            }
            return .map(keys, dict)
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
    case value(MsgPackValue)
    case encoder(_MsgPackEncoder)
    case nestedArray(RefArray)
    case nestedMap(RefMap)

    class RefArray {
        private(set) var array: [MsgPackFuture] = []

        init() {
            array.reserveCapacity(10)
        }

        @inline(__always)
        func append(_ element: MsgPackValue) {
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

        var values: [MsgPackValue] {
            array.compactMap { future in
                switch future {
                case let .value(value):
                    return value
                case let .nestedArray(array):
                    return .array(array.values)
                case let .nestedMap(map):
                    let values = map.values
                    let n = values.count
                    var keys: [MsgPackValue] = []
                    keys.reserveCapacity(n)
                    var dict: [MsgPackValue: MsgPackValue] = [:]
                    dict.reserveCapacity(n)
                    for (k, v) in values {
                        keys.append(k)
                        dict[k] = v
                    }
                    return .map(keys, dict)
                case let .encoder(encoder):
                    return encoder.value
                }
            }
        }
    }

    class RefMap {
        private(set) var keys: [MsgPackValue] = []
        private(set) var dict: [MsgPackValue: MsgPackFuture] = [:]
        init() {
            dict.reserveCapacity(20)
        }

        @inline(__always)
        func set(_ value: MsgPackValue, for key: MsgPackValue) {
            keys.append(key)
            dict[key] = .value(value)
        }

        @inline(__always)
        func setArray(for key: MsgPackValue) -> RefArray {
            switch dict[key] {
            case let .nestedArray(array):
                return array
            case .none, .value:
                let array: MsgPackFuture.RefArray = .init()
                dict[key] = .nestedArray(array)
                keys.append(key)
                return array
            case .nestedMap:
                preconditionFailure("For key \"\(key)\" a keyed container has already been created.")
            case .encoder:
                preconditionFailure("For key \"\(key)\" an encoder has already been created.")
            }
        }

        @inline(__always)
        func setMap(for key: MsgPackValue) -> RefMap {
            switch dict[key] {
            case let .nestedMap(map):
                return map
            case .none, .value:
                let map: MsgPackFuture.RefMap = .init()
                dict[key] = .nestedMap(map)
                keys.append(key)
                return map
            case .nestedArray:
                preconditionFailure("For key \"\(key)\" a unkeyed container has already been created.")
            case .encoder:
                preconditionFailure("For key \"\(key)\" an encoder has already been created.")
            }
        }

        @inline(__always)
        func set(_ encoder: _MsgPackEncoder, for key: MsgPackValue) {
            switch dict[key] {
            case .encoder:
                preconditionFailure("For key \"\(key)\" an encoder has already been created.")
            case .nestedMap:
                preconditionFailure("For key \"\(key)\" a keyed container has already been created.")
            case .nestedArray:
                preconditionFailure("For key \"\(key)\" a unkeyed container has already been created.")
            case .none, .value:
                dict[key] = .encoder(encoder)
                keys.append(key)
            }
        }

        var values: [(MsgPackValue, MsgPackValue)] {
            keys.compactMap {
                guard let value = self.dict[$0] else {
                    return nil
                }
                switch value {
                case let .value(value):
                    return ($0, value)
                case let .nestedArray(array):
                    return ($0, .array(array.values))
                case let .nestedMap(map):
                    var keys: [MsgPackValue] = []
                    var dict: [MsgPackValue: MsgPackValue] = [:]
                    for (k, v) in map.values {
                        keys.append(k)
                        dict[k] = v
                    }
                    return ($0, .map(keys, dict))
                case let .encoder(encoder):
                    guard let value = encoder.value else {
                        return nil
                    }
                    return ($0, value)
                }
            }
        }
    }
}

private protocol _SpecialTreatmentEncoder {
    var codingPath: [CodingKey] { get }
    var encoder: _MsgPackEncoder { get }
}

private extension _SpecialTreatmentEncoder {
    func wrapFloat<F: FloatingPoint & DataNumber>(_ value: F, for additionalKey: CodingKey?) throws -> MsgPackValue {
        var data: Data = .init()
        let bits = value.data
        if bits.count == 4 {
            data.append(contentsOf: [0xCA])
            data.append(bits)
            return .literal(.float(data))
        }
        if bits.count == 8 {
            data.append(contentsOf: [0xCB])
            data.append(bits)
            return .literal(.float(data))
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

    func wrapInt<T: SignedInteger>(_ value: T, for additionalKey: CodingKey?) throws -> MsgPackValue {
        if Int.fixMin <= value, value <= Int.fixMax {
            let v: Int8 = .init(value)
            let bits = withUnsafePointer(to: v.bigEndian) {
                Data(buffer: UnsafeBufferPointer(start: $0, count: 1))
            }
            return .literal(.int(.init(bits)))
        }
        if Int8.min <= value, value <= Int8.max {
            let v: Int8 = .init(value)
            let bits = withUnsafePointer(to: v.bigEndian) {
                Data(buffer: UnsafeBufferPointer(start: $0, count: 1))
            }
            var data = Data([0xD0])
            data.append(bits)
            return .literal(.int(data))
        }
        if Int16.min <= value, value <= Int16.max {
            let v: Int16 = .init(value)
            let bits = withUnsafePointer(to: v.bigEndian) {
                Data(buffer: UnsafeBufferPointer(start: $0, count: 1))
            }
            var data = Data([0xD1])
            data.append(bits)
            return .literal(.int(data))
        }
        if Int32.min <= value, value <= Int32.max {
            let v: Int32 = .init(value)
            let bits = withUnsafePointer(to: v.bigEndian) {
                Data(buffer: UnsafeBufferPointer(start: $0, count: 1))
            }
            var data = Data([0xD2])
            data.append(bits)
            return .literal(.int(data))
        }
        if Int64.min <= value, value <= Int64.max {
            let v: Int64 = .init(value)
            let bits = withUnsafePointer(to: v.bigEndian) {
                Data(buffer: UnsafeBufferPointer(start: $0, count: 1))
            }
            var data = Data([0xD3])
            data.append(bits)
            return .literal(.int(data))
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

    func wrapUInt<T: UnsignedInteger>(_ value: T, for additionalKey: CodingKey?) throws -> MsgPackValue {
        if value <= Int.fixMax {
            return .literal(.uint(.init([UInt8(value)])))
        }
        if value <= UInt8.max {
            return .literal(.uint(.init([0xCC, UInt8(value)])))
        }
        if value <= UInt16.max {
            let v: UInt16 = .init(value)
            let bits = withUnsafePointer(to: v.bigEndian) {
                Data(buffer: UnsafeBufferPointer(start: $0, count: 1))
            }
            var data = Data([0xCD])
            data.append(bits)
            return .literal(.uint(data))
        }
        if value <= UInt32.max {
            let v: UInt32 = .init(value)
            let bits = withUnsafePointer(to: v.bigEndian) {
                Data(buffer: UnsafeBufferPointer(start: $0, count: 1))
            }
            var data = Data([0xCE])
            data.append(bits)
            return .literal(.uint(data))
        }
        if value <= UInt64.max {
            let v: UInt64 = .init(value)
            let bits = withUnsafePointer(to: v.bigEndian) {
                Data(buffer: UnsafeBufferPointer(start: $0, count: 1))
            }
            var data = Data([0xCF])
            data.append(bits)
            return .literal(.uint(data))
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

    func wrapBool(_ value: Bool) -> MsgPackValue {
        .literal(.bool(value))
    }

    func wrapString(_ value: String, for additionalKey: CodingKey?) throws -> MsgPackValue {
        let n = value.count
        if n <= UInt.maxUint5 {
            var bb: [UInt8] = [UInt8(0xA0 + n)]
            bb.append(contentsOf: value.utf8)
            return .literal(.str(.init(bb)))
        } else if n <= UInt8.max {
            var bb: [UInt8] = [0xD9, UInt8(n)]
            bb.append(contentsOf: value.utf8)
            return .literal(.str(.init(bb)))
        } else if n <= UInt16.max {
            var bb: [UInt8] = [0xDA]
            bb.append(contentsOf: withUnsafePointer(to: UInt16(n).bigEndian) {
                Data(buffer: UnsafeBufferPointer(start: $0, count: 1))
            })
            bb.append(contentsOf: value.utf8)
            return .literal(.str(.init(bb)))
        } else if n <= UInt32.max {
            var bb: [UInt8] = [0xDB]
            bb.append(contentsOf: withUnsafePointer(to: UInt32(n).bigEndian) {
                Data(buffer: UnsafeBufferPointer(start: $0, count: 1))
            })
            bb.append(contentsOf: value.utf8)
            return .literal(.str(.init(bb)))
        }
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

    func wrapEncodable<E: Encodable>(_ encodable: E, for additionalKey: CodingKey?) throws -> MsgPackValue? {
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

    func wrapData(_ data: Data, for _: CodingKey?) throws -> MsgPackValue {
        let value = [UInt8](data)
        let n = value.count
        var bb: [UInt8] = []
        bb.append(0xC4)
        bb.append(UInt8(n))
        bb.append(contentsOf: value)
        return .literal(.bin(.init(bb)))
    }

    func wrapMsgPackEncodable(_ encodable: MsgPackEncodable, for additionalKey: CodingKey?) throws -> MsgPackValue {
        var d: Data = .init()
        let data = try encodable.encodeMsgPack()
        let n = data.count
        switch n {
        case 1:
            d.append(.init([0xD4]))
        case 2:
            d.append(.init([0xD5]))
        case 4:
            d.append(.init([0xD6]))
        case 8:
            d.append(.init([0xD7]))
        case 16:
            d.append(.init([0xD8]))
        default:
            if n <= UInt8.max {
                d.append(.init([0xC7]))
                d.append(withUnsafePointer(to: UInt8(n).bigEndian) {
                    Data(buffer: UnsafeBufferPointer(start: $0, count: 1))
                })
            } else if n <= UInt16.max {
                d.append(.init([0xC8]))
                d.append(withUnsafePointer(to: UInt16(n).bigEndian) {
                    Data(buffer: UnsafeBufferPointer(start: $0, count: 1))
                })
            } else if n <= UInt32.max {
                d.append(.init([0xC9]))
                d.append(withUnsafePointer(to: UInt32(n).bigEndian) {
                    Data(buffer: UnsafeBufferPointer(start: $0, count: 1))
                })
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
        d.append(withUnsafePointer(to: encodable.type.bigEndian) {
            Data(buffer: UnsafeBufferPointer(start: $0, count: 1))
        })
        d.append(data)
        return .ext(encodable.type, d)
    }

    func getEncoder(for additionalKey: CodingKey?) -> _MsgPackEncoder {
        if let additionalKey = additionalKey {
            let newCodidngPath: [CodingKey] = codingPath + [additionalKey]
            return _MsgPackEncoder(codingPath: newCodidngPath)
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

    public func encode(_ value: UInt) throws {
        encoder.singleValue = try encoder.wrapUInt(value, for: nil)
    }

    public func encode(_ value: UInt8) throws {
        encoder.singleValue = try encoder.wrapUInt(value, for: nil)
    }

    public func encode(_ value: UInt16) throws {
        encoder.singleValue = try encoder.wrapUInt(value, for: nil)
    }

    public func encode(_ value: UInt32) throws {
        encoder.singleValue = try encoder.wrapUInt(value, for: nil)
    }

    public func encode(_ value: UInt64) throws {
        encoder.singleValue = try encoder.wrapUInt(value, for: nil)
    }

    public func encode<T>(_ value: T) throws where T: Encodable {
        encoder.singleValue = try wrapEncodable(value, for: nil)
    }

    @inline(__always)
    private func encodeInt<T: SignedInteger>(_ value: T) throws {
        encoder.singleValue = try encoder.wrapInt(value, for: nil)
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
        array.append(try encoder.wrapString(value, for: nil))
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

    private func encodeUInt<T: UnsignedInteger>(_ value: T) throws {
        array.append(try encoder.wrapUInt(value, for: nil))
    }

    private func encodeInt<T: SignedInteger>(_ value: T) throws {
        array.append(try encoder.wrapInt(value, for: nil))
    }

    private func encodeFloat<T: FloatingPoint & DataNumber>(_ value: T) throws {
        array.append(try encoder.wrapFloat(value, for: nil))
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
        map.set(.Nil, for: try encoder.wrapString(key.stringValue, for: key))
    }

    func encode(_ value: Bool, forKey key: Key) throws {
        let value = encoder.wrapBool(value)
        map.set(value, for: try encoder.wrapString(key.stringValue, for: key))
    }

    func encode(_ value: String, forKey key: Key) throws {
        let value = try encoder.wrapString(value, for: key)
        map.set(value, for: try encoder.wrapString(key.stringValue, for: key))
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

    func encode<T>(_ value: T, forKey key: Key) throws where T: Encodable {
        let encoded = try encoder.wrapEncodable(value, for: key)
        map.set(encoded ?? .Nil, for: try encoder.wrapString(key.stringValue, for: key))
    }

    func nestedContainer<NestedKey>(keyedBy _: NestedKey.Type, forKey key: Key) -> KeyedEncodingContainer<NestedKey> where NestedKey: CodingKey {
        let newPath = codingPath + [key]
        let map: MsgPackFuture.RefMap = map.setMap(for: try! encoder.wrapString(key.stringValue, for: key))
        let nestedContainer = MsgPackKeyedEncodingContainer<NestedKey>(referencing: encoder, map: map, codingPath: newPath)
        return KeyedEncodingContainer(nestedContainer)
    }

    func nestedUnkeyedContainer(forKey key: Self.Key) -> UnkeyedEncodingContainer {
        let newPath = codingPath + [key]
        let array: MsgPackFuture.RefArray = map.setArray(for: try! encoder.wrapString(key.stringValue, for: key))
        let nestedContainer = MsgPackUnkeyedEncodingContainer(referencing: encoder, array: array, codingPath: newPath)
        return nestedContainer
    }

    func superEncoder() -> Encoder {
        let newEncoder = encoder.getEncoder(for: MsgPackKey.super)
        map.set(newEncoder, for: try! encoder.wrapString(MsgPackKey.super.stringValue, for: nil))
        return newEncoder
    }

    func superEncoder(forKey key: Key) -> Encoder {
        let newEncoder = encoder.getEncoder(for: key)
        map.set(newEncoder, for: try! encoder.wrapString(key.stringValue, for: key))
        return newEncoder
    }

    private func encodeFloat<T: FloatingPoint & DataNumber>(_ value: T, for key: Key) throws {
        let value = try encoder.wrapFloat(value, for: nil)
        map.set(value, for: try encoder.wrapString(key.stringValue, for: key))
    }

    private func encodeInt<T: SignedInteger>(_ value: T, for key: Key) throws {
        let value = try encoder.wrapInt(value, for: key)
        map.set(value, for: try encoder.wrapString(key.stringValue, for: key))
    }

    private func encodeUInt<T: UnsignedInteger>(_ value: T, forKey key: Key) throws {
        let value = try encoder.wrapUInt(value, for: key)
        map.set(value, for: try encoder.wrapString(key.stringValue, for: key))
    }
}

extension MsgPackKeyedEncodingContainer {
    public mutating func encodeIfPresent<T: Encodable>(
        _ value: T?,
        forKey key: Key
    ) throws {
        let keyValue = try! encoder.wrapString(key.stringValue, for: key)
        switch value {
        case let .some(v):
            let value = try encoder.wrapEncodable(v, for: key)!

            map.set(value, for: keyValue)
        case .none:
            map.set(.Nil, for: keyValue)
        }
    }
}

internal struct MsgPackKey: CodingKey {
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

internal func bigEndianUInt(_ data: Data) throws -> UInt {
    switch data.count {
    case 1:
        return UInt(UInt8(bigEndian: data.withUnsafeBytes { $0.baseAddress?.assumingMemoryBound(to: UInt8.self).pointee ?? 0 }))
    case 2:
        return UInt(UInt16(bigEndian: data.withUnsafeBytes { $0.baseAddress?.assumingMemoryBound(to: UInt16.self).pointee ?? 0 }))
    case 4:
        return UInt(UInt32(bigEndian: data.withUnsafeBytes { $0.baseAddress?.assumingMemoryBound(to: UInt32.self).pointee ?? 0 }))
    case 8:
        return UInt(UInt64(bigEndian: data.withUnsafeBytes { $0.baseAddress?.assumingMemoryBound(to: UInt64.self).pointee ?? 0 }))
    default:
        throw MsgPackDecodingError.dataCorrupted
    }
}

internal func bigEndianInt(_ data: Data) throws -> Int {
    switch data.count {
    case 1:
        return Int(Int8(bigEndian: data.withUnsafeBytes { $0.baseAddress?.assumingMemoryBound(to: Int8.self).pointee ?? 0 }))
    case 2:
        return Int(Int16(bigEndian: data.withUnsafeBytes { $0.baseAddress?.assumingMemoryBound(to: Int16.self).pointee ?? 0 }))
    case 4:
        return Int(Int32(bigEndian: data.withUnsafeBytes { $0.baseAddress?.assumingMemoryBound(to: Int32.self).pointee ?? 0 }))
    case 8:
        return Int(Int64(bigEndian: data.withUnsafeBytes { $0.baseAddress?.assumingMemoryBound(to: Int64.self).pointee ?? 0 }))
    default:
        throw MsgPackDecodingError.dataCorrupted
    }
}

private extension Int {
    static let fixMax = 0x7F
    static let fixMin = -0x20
}

extension UInt {
    static let maxUint4 = 1 << 4 - 1
    static let maxUint5 = 1 << 5 - 1
}
