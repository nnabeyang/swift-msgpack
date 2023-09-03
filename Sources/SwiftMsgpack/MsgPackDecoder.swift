import Foundation

private protocol _MsgPackDictionaryDecodableMarker {}

extension Dictionary: _MsgPackDictionaryDecodableMarker where Key: Encodable, Value: Decodable {}

private protocol _MsgPackArrayDecodableMarker {}

extension Array: _MsgPackArrayDecodableMarker where Element: Decodable {}

open class MsgPackDecoder {
    public init() {}
    open func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let scanner: MsgPackScanner = .init(data: data)
        var value: MsgPackValue = .none
        try scanner.parse(&value)
        let decoder: _MsgPackDecoder = .init(from: value)
        do {
            return try decoder.unwrap(as: T.self)
        } catch {
            if let error = error as? MsgPackDecodingError {
                throw error.asDecodingError(type, codingPath: [])
            }
            throw error
        }
    }
}

public protocol MsgPackDecodable: Decodable {
    var type: Int8 { get }
    init(msgPack data: Data) throws
}

public typealias MsgPackCodable = MsgPackEncodable & MsgPackDecodable

private class _MsgPackDecoder: Decoder {
    var codingPath: [CodingKey]
    var value: MsgPackValue
    var userInfo: [CodingUserInfoKey: Any] = [:]

    init(from value: MsgPackValue, at codingPath: [CodingKey] = []) {
        self.value = value
        self.codingPath = codingPath
    }

    func container<Key>(keyedBy _: Key.Type) throws -> KeyedDecodingContainer<Key> where Key: CodingKey {
        guard case .map = value else {
            throw DecodingError.typeMismatch([MsgPackValue: MsgPackValue].self, DecodingError.Context(
                codingPath: codingPath,
                debugDescription: "Expected to decode \([MsgPackValue: MsgPackValue].self) but found \(value.debugDataTypeDescription) instead."
            ))
        }
        return KeyedDecodingContainer(MsgPackKeyedDecodingContainer<Key>(referencing: self, container: value))
    }

    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        switch value {
        case .array: break
        case .none: break
        case .map:
            value = value.asArray()
        default:
            throw DecodingError.typeMismatch([MsgPackValue].self, DecodingError.Context(
                codingPath: codingPath,
                debugDescription: "Expected to decode \([MsgPackValue].self) but found \(value.debugDataTypeDescription) instead."
            ))
        }

        return MsgPackUnkeyedUnkeyedDecodingContainer(referencing: self, container: value)
    }

    func singleValueContainer() throws -> SingleValueDecodingContainer {
        _MsgPackSingleValueDecodingContainer(decoder: self, codingPath: codingPath, value: value)
    }
}

private extension _MsgPackDecoder {
    func unbox(_ value: MsgPackValue, as type: Bool.Type) throws -> Bool? {
        if value == .Nil {
            return nil
        }
        if case let .literal(.bool(v)) = value {
            return v
        }

        throw DecodingError.typeMismatch(type, DecodingError.Context(
            codingPath: codingPath,
            debugDescription: "Expected to decode \(type) but found \(value.debugDataTypeDescription) instead."
        ))
    }

    func unbox(_ value: MsgPackValue, as type: String.Type) throws -> String? {
        if value == .Nil {
            return nil
        }
        if case let .literal(.str(v)) = value {
            guard let s = String(data: v, encoding: .utf8) else {
                throw MsgPackDecodingError.dataCorrupted
            }
            return s
        }

        throw DecodingError.typeMismatch(type, DecodingError.Context(
            codingPath: codingPath,
            debugDescription: "Expected to decode \(type) but found \(value.debugDataTypeDescription) instead."
        ))
    }

    func unboxFloat<T: BinaryFloatingPoint & DataNumber>(_ value: MsgPackValue, as type: T.Type) throws -> T? {
        if value == .Nil {
            return nil
        }
        if case let .literal(v) = value {
            switch v {
            case .float:
                return try type.init(data: v.data)
            case .uint:
                return T(try bigEndianUInt(v.data))
            case .int:
                return T(try bigEndianInt(v.data))
            default:
                break
            }
        }
        throw DecodingError.typeMismatch(type, DecodingError.Context(
            codingPath: codingPath,
            debugDescription: "Expected to decode \(type) but found \(value.debugDataTypeDescription) instead."
        ))
    }
    
    func unboxInt<T: SignedInteger>(_ value: MsgPackValue, as type: T.Type) throws -> T? {
        if value == .Nil {
            return nil
        }
        if case let .literal(vv) = value {
            switch vv {
            case .uint:
                let v = try bigEndianUInt(vv.data)
                guard let r=T(exactly:v ) else {
                    throw DecodingError.typeMismatch(type, DecodingError.Context(
                        codingPath: codingPath,
                        debugDescription: "Expected to decode \(type) but found \(v)(\(value.debugDataTypeDescription)) instead."
                    ))
                }
                return r
            case .int:
                let v = try bigEndianInt(vv.data)
                guard let r=T(exactly:v ) else {
                    throw DecodingError.typeMismatch(type, DecodingError.Context(
                        codingPath: codingPath,
                        debugDescription: "Expected to decode \(type) but found \(v)(\(value.debugDataTypeDescription)) instead."
                    ))
                }
                return r
            default:
                break
            }
        }

        throw DecodingError.typeMismatch(type, DecodingError.Context(
            codingPath: codingPath,
            debugDescription: "Expected to decode \(type) but found \(value.debugDataTypeDescription) instead."
        ))
    }

    func unboxUInt<T: UnsignedInteger>(_ value: MsgPackValue, as type: T.Type) throws -> T? {
        if value == .Nil {
            return nil
        }
        if case let .literal(.uint(v)) = value {
            return try type.init(bigEndianUInt(v))
        }

        throw DecodingError.typeMismatch(type, DecodingError.Context(
            codingPath: codingPath,
            debugDescription: "Expected to decode \(type) but found \(value.debugDataTypeDescription) instead."
        ))
    }
}

extension _MsgPackDecoder {
    func unwrap<T: Decodable>(as type: T.Type) throws -> T {
        if type == Data.self || type == NSData.self {
            return try unwrapData() as! T
        }
        if let type = type as? MsgPackDecodable.Type {
            let value = try unwrapMsgPackDecodable(as: type)
            guard let ret = value as? T else {
                throw MsgPackDecodingError.dataCorrupted
            }
            return ret
        }
        if T.self is _MsgPackDictionaryDecodableMarker.Type {
            try checkDictionay(as: T.self)
        }
        if T.self is _MsgPackArrayDecodableMarker.Type {
            try checkArray(as: T.self)
        }
        return try T(from: self)
    }

    func unwrapData() throws -> Data {
        guard case let .literal(.bin(v)) = value else {
            throw DecodingError.typeMismatch(Data.self, DecodingError.Context(codingPath: codingPath, debugDescription: ""))
        }
        return v
    }

    func unwrapMsgPackDecodable(as type: MsgPackDecodable.Type) throws -> MsgPackDecodable {
        guard case let .ext(typeNo, data) = value else {
            throw DecodingError.typeMismatch(MsgPackDecodable.self, DecodingError.Context(codingPath: codingPath, debugDescription: ""))
        }
        let value = try type.init(msgPack: data)
        guard value.type == typeNo else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: codingPath, debugDescription: "extension type number mismatch: expected: \(value.type) got: \(typeNo)"))
        }
        return value
    }

    private func checkDictionay<T: Decodable>(as _: T.Type) throws {
        guard (T.self as? (_MsgPackDictionaryDecodableMarker & Decodable).Type) != nil else {
            preconditionFailure("Must only be called of T implements _MsgPackDictionaryDecodableMarker")
        }
        guard case .map = value else {
            throw DecodingError.typeMismatch([MsgPackValue: MsgPackValue].self, DecodingError.Context(
                codingPath: codingPath,
                debugDescription: "Expected to decode \([MsgPackValue: MsgPackValue].self) but found \(value.debugDataTypeDescription) instead."
            ))
        }
    }

    private func checkArray<T: Decodable>(as _: T.Type) throws {
        guard (T.self as? (_MsgPackArrayDecodableMarker & Decodable).Type) != nil else {
            preconditionFailure("Must only be called of T implements _MsgPackArrayDecodableMarker")
        }
        guard case .array = value else {
            throw DecodingError.typeMismatch([MsgPackValue].self, DecodingError.Context(
                codingPath: codingPath,
                debugDescription: "Expected to decode \([MsgPackValue].self) but found \(value.debugDataTypeDescription) instead."
            ))
        }
    }
}

private struct _MsgPackSingleValueDecodingContainer: SingleValueDecodingContainer {
    let decoder: _MsgPackDecoder
    let codingPath: [CodingKey]
    let value: MsgPackValue

    init(decoder: _MsgPackDecoder, codingPath: [CodingKey], value: MsgPackValue) {
        self.decoder = decoder
        self.codingPath = codingPath
        self.value = value
    }

    func decodeNil() -> Bool {
        value == .Nil
    }

    func decode(_: Bool.Type) throws -> Bool {
        guard let b = try decoder.unbox(value, as: Bool.self) else {
            throw MsgPackDecodingError.dataCorrupted
        }
        return b
    }

    func decode(_ type: String.Type) throws -> String {
        guard let s = try decoder.unbox(value, as: String.self) else {
            throw MsgPackDecodingError.dataCorrupted
        }
        return s
    }

    func decode(_ type: Double.Type) throws -> Double {
        guard let d = try decoder.unboxFloat(value, as: type) else {
            throw MsgPackDecodingError.dataCorrupted
        }
        return d
    }

    func decode(_ type: Float.Type) throws -> Float {
        guard let f = try decoder.unboxFloat(value, as: type) else {
            throw MsgPackDecodingError.dataCorrupted
        }
        return f
    }

    func decode(_ type: Int.Type) throws -> Int {
        guard let i = try decoder.unboxInt(value, as: type) else {
            throw MsgPackDecodingError.dataCorrupted
        }
        return i
    }

    func decode(_ type: Int8.Type) throws -> Int8 {
        guard let i = try decoder.unboxInt(value, as: type) else {
            throw MsgPackDecodingError.dataCorrupted
        }
        return i
    }

    func decode(_ type: Int16.Type) throws -> Int16 {
        guard let i = try decoder.unboxInt(value, as: type) else {
            throw MsgPackDecodingError.dataCorrupted
        }
        return i
    }

    func decode(_ type: Int32.Type) throws -> Int32 {
        guard let i = try decoder.unboxInt(value, as: type) else {
            throw MsgPackDecodingError.dataCorrupted
        }
        return i
    }

    func decode(_ type: Int64.Type) throws -> Int64 {
        guard let i = try decoder.unboxInt(value, as: type) else {
            throw MsgPackDecodingError.dataCorrupted
        }
        return i
    }

    func decode(_ type: UInt.Type) throws -> UInt {
        guard let i = try decoder.unboxUInt(value, as: type) else {
            throw MsgPackDecodingError.dataCorrupted
        }
        return i
    }

    func decode(_ type: UInt8.Type) throws -> UInt8 {
        guard let i = try decoder.unboxUInt(value, as: type) else {
            throw MsgPackDecodingError.dataCorrupted
        }
        return i
    }

    func decode(_ type: UInt16.Type) throws -> UInt16 {
        guard let i = try decoder.unboxUInt(value, as: type) else {
            throw MsgPackDecodingError.dataCorrupted
        }
        return i
    }

    func decode(_ type: UInt32.Type) throws -> UInt32 {
        guard let i = try decoder.unboxUInt(value, as: type) else {
            throw MsgPackDecodingError.dataCorrupted
        }
        return i
    }

    func decode(_ type: UInt64.Type) throws -> UInt64 {
        guard let i = try decoder.unboxUInt(value, as: type) else {
            throw MsgPackDecodingError.dataCorrupted
        }
        return i
    }

    func decode<T>(_ type: T.Type) throws -> T where T: Decodable {
        try decoder.unwrap(as: type)
    }
}

private struct MsgPackUnkeyedUnkeyedDecodingContainer: UnkeyedDecodingContainer {
    private let decoder: _MsgPackDecoder
    private(set) var codingPath: [CodingKey]
    public private(set) var currentIndex: Int
    private var container: MsgPackValue

    init(referencing decoder: _MsgPackDecoder, container: MsgPackValue) {
        self.decoder = decoder
        codingPath = decoder.codingPath
        currentIndex = 0
        self.container = container
    }

    var count: Int? {
        container.count
    }

    var isAtEnd: Bool {
        self.currentIndex >= self.count!
    }

    mutating func decodeNil() throws -> Bool {
        let value = try getNextValue(ofType: Never.self)
        if value == .Nil {
            currentIndex += 1
            return true
        }
        return false
    }

    mutating func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> where NestedKey: CodingKey {
        let decoder = try decoderForNextElement(ofType: UnkeyedDecodingContainer.self)
        let container: KeyedDecodingContainer = try decoder.container(keyedBy: type)
        currentIndex += 1
        return container
    }

    mutating func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
        let decoder = try decoderForNextElement(ofType: UnkeyedDecodingContainer.self)
        let container: UnkeyedDecodingContainer = try decoder.unkeyedContainer()
        currentIndex += 1
        return container
    }

    mutating func superDecoder() throws -> Decoder {
        let decoder = try decoderForNextElement(ofType: Decoder.self)
        currentIndex += 1
        return decoder
    }

    mutating func decode(_: Bool.Type) throws -> Bool {
        let value = try getNextValue(ofType: String.self)
        currentIndex += 1
        guard let r = try decoder.unbox(value, as: Bool.self) else {
            throw MsgPackDecodingError.dataCorrupted
        }
        return r
    }

    mutating func decode(_: String.Type) throws -> String {
        let value = try getNextValue(ofType: String.self)
        currentIndex += 1
        guard let s = try decoder.unbox(value, as: String.self) else {
            throw MsgPackDecodingError.dataCorrupted
        }
        return s
    }

    mutating func decode(_: Double.Type) throws -> Double {
        try decodeFloat(as: Double.self)
    }

    mutating func decode(_: Float.Type) throws -> Float {
        try decodeFloat(as: Float.self)
    }

    mutating func decode(_: Int.Type) throws -> Int {
        try decodeInt(as: Int.self)
    }

    mutating func decode(_: Int8.Type) throws -> Int8 {
        try decodeInt(as: Int8.self)
    }

    mutating func decode(_: Int16.Type) throws -> Int16 {
        try decodeInt(as: Int16.self)
    }

    mutating func decode(_: Int32.Type) throws -> Int32 {
        try decodeInt(as: Int32.self)
    }

    mutating func decode(_: Int64.Type) throws -> Int64 {
        try decodeInt(as: Int64.self)
    }

    mutating func decode(_: UInt.Type) throws -> UInt {
        try decodeUInt(as: UInt.self)
    }

    mutating func decode(_: UInt8.Type) throws -> UInt8 {
        try decodeUInt(as: UInt8.self)
    }

    mutating func decode(_: UInt16.Type) throws -> UInt16 {
        try decodeUInt(as: UInt16.self)
    }

    mutating func decode(_: UInt32.Type) throws -> UInt32 {
        try decodeUInt(as: UInt32.self)
    }

    mutating func decode(_: UInt64.Type) throws -> UInt64 {
        try decodeUInt(as: UInt64.self)
    }

    mutating func decode<T>(_ type: T.Type) throws -> T where T: Decodable {
        let newDecoder: _MsgPackDecoder = try decoderForNextElement(ofType: T.self)
        do {
            let result: T = try newDecoder.unwrap(as: T.self)
            currentIndex += 1
            return result
        } catch {
            if let error = error as? MsgPackDecodingError {
                throw error.asDecodingError(type, codingPath: codingPath)
            }
            throw error
        }
    }

    private mutating func decoderForNextElement<T>(ofType _: T.Type) throws -> _MsgPackDecoder {
        let value = try getNextValue(ofType: T.self)
        let newPath = codingPath + [MsgPackKey(index: currentIndex)]
        return _MsgPackDecoder(from: value, at: newPath)
    }

    @inline(__always)
    private func getNextValue<T>(ofType _: T.Type) throws -> MsgPackValue {
        guard !isAtEnd else {
            let message: String
            if T.self == MsgPackUnkeyedUnkeyedDecodingContainer.self {
                message = "Cannot get nested unkeyed container -- unkeyed container is at end."
            } else if T.self == Decoder.self {
                message = "Cannot get superDecoder() -- unkeyed container is at end."
            } else {
                message = "Unkeyed container is at end."
            }

            var path = codingPath
            path.append(MsgPackKey(index: currentIndex))

            throw DecodingError.valueNotFound(
                T.self,
                .init(codingPath: path,
                      debugDescription: message,
                      underlyingError: nil)
            )
        }
        return container[currentIndex]
    }

    @inline(__always)
    private mutating func decodeUInt<T: UnsignedInteger>(as _: T.Type) throws -> T {
        let value = try getNextValue(ofType: T.self)
        guard let result = try decoder.unboxUInt(value, as: T.self) else {
            throw MsgPackDecodingError.dataCorrupted
        }
        currentIndex += 1
        return result
    }

    @inline(__always)
    private mutating func decodeInt<T: SignedInteger>(as _: T.Type) throws -> T {
        let value = try getNextValue(ofType: T.self)
        guard let result = try decoder.unboxInt(value, as: T.self) else {
            throw MsgPackDecodingError.dataCorrupted
        }
        currentIndex += 1
        return result
    }

    @inline(__always)
    private mutating func decodeFloat<T: BinaryFloatingPoint & DataNumber>(as _: T.Type) throws -> T {
        let value = try getNextValue(ofType: T.self)
        guard let result = try decoder.unboxFloat(value, as: T.self) else {
            throw MsgPackDecodingError.dataCorrupted
        }
        currentIndex += 1
        return result
    }
}

private struct MsgPackKeyedDecodingContainer<K: CodingKey>: KeyedDecodingContainerProtocol {
    typealias Key = K

    private let decoder: _MsgPackDecoder
    private(set) var codingPath: [CodingKey]
    private var container: MsgPackValue

    init(referencing decoder: _MsgPackDecoder, container: MsgPackValue) {
        self.decoder = decoder
        self.container = container
        codingPath = decoder.codingPath
    }

    var allKeys: [Key] {
        container.keys.compactMap {
            guard let stringValue = try? decoder.unbox($0, as: String.self) else {
                return nil
            }
            return Key(stringValue: stringValue)
        }
    }

    func contains(_ key: Key) -> Bool {
        container[.init(stringLiteral: key.stringValue)] != nil
    }

    func decodeNil(forKey key: Key) throws -> Bool {
        let value = try getValue(forKey: key)
        return value == .Nil
    }

    func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool {
        let value = try getValue(forKey: key)
        guard let v = try decoder.unbox(value, as: type) else {
            throw MsgPackDecodingError.dataCorrupted
        }
        return v
    }

    func decode(_ type: String.Type, forKey key: Key) throws -> String {
        let value = try getValue(forKey: key)
        guard let r = try decoder.unbox(value, as: type) else {
            throw MsgPackDecodingError.dataCorrupted
        }
        return r
    }

    func decode(_: Double.Type, forKey key: Key) throws -> Double {
        try decodeFloat(key: key)
    }

    func decode(_: Float.Type, forKey key: Key) throws -> Float {
        try decodeFloat(key: key)
    }

    func decode(_: Int.Type, forKey key: Key) throws -> Int {
        try decodeInt(key: key)
    }

    func decode(_: Int8.Type, forKey key: Key) throws -> Int8 {
        try decodeInt(key: key)
    }

    func decode(_: Int16.Type, forKey key: Key) throws -> Int16 {
        try decodeInt(key: key)
    }

    func decode(_: Int32.Type, forKey key: Key) throws -> Int32 {
        try decodeInt(key: key)
    }

    func decode(_: Int64.Type, forKey key: Key) throws -> Int64 {
        try decodeInt(key: key)
    }

    func decode(_: UInt.Type, forKey key: Key) throws -> UInt {
        try decodeUInt(key: key)
    }

    func decode(_: UInt8.Type, forKey key: Key) throws -> UInt8 {
        try decodeUInt(key: key)
    }

    func decode(_: UInt16.Type, forKey key: Key) throws -> UInt16 {
        try decodeUInt(key: key)
    }

    func decode(_: UInt32.Type, forKey key: Key) throws -> UInt32 {
        try decodeUInt(key: key)
    }

    func decode(_: UInt64.Type, forKey key: Key) throws -> UInt64 {
        try decodeUInt(key: key)
    }

    func decode<T>(_ type: T.Type, forKey key: Key) throws -> T where T: Decodable {
        let newDecoder: _MsgPackDecoder = try decoderForKey(key)
        do {
            return try newDecoder.unwrap(as: T.self)
        } catch {
            if let error = error as? MsgPackDecodingError {
                throw error.asDecodingError(type, codingPath: codingPath)
            }
            throw error
        }
    }

    func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> where NestedKey: CodingKey {
        try decoderForKey(key).container(keyedBy: type)
    }

    func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
        try decoderForKey(key).unkeyedContainer()
    }

    func superDecoder() throws -> Decoder {
        try decoderForKey(MsgPackKey.super)
    }

    func superDecoder(forKey key: Key) throws -> Decoder {
        try decoderForKey(key)
    }

    private func decoderForKey<LocalKey: CodingKey>(_ key: LocalKey) throws -> _MsgPackDecoder {
        let value = try getValue(forKey: key)
        let newPath: [CodingKey] = codingPath + [key]
        return _MsgPackDecoder(from: value, at: newPath)
    }

    @inline(__always)
    private func getValue<LocalKey: CodingKey>(forKey key: LocalKey) throws -> MsgPackValue {
        guard let value = container[.init(stringLiteral: key.stringValue)] else {
            let context = DecodingError.Context(codingPath: codingPath, debugDescription: "No value assosiated with key \(key) (\"\(key.stringValue)\"")
            throw DecodingError.keyNotFound(key, context)
        }
        return value
    }

    @inline(__always)
    private func decodeFloat<T: BinaryFloatingPoint & DataNumber>(key: K) throws -> T {
        let value = try getValue(forKey: key)
        guard let r = try decoder.unboxFloat(value, as: T.self) else {
            throw MsgPackDecodingError.dataCorrupted
        }
        return r
    }

    @inline(__always)
    private func decodeInt<T: SignedInteger>(key: K) throws -> T {
        let value = try getValue(forKey: key)
        do {
            return try decoder.unboxInt(value, as: T.self)!
        } catch {
            if let error = error as? MsgPackDecodingError {
                throw error.asDecodingError(T.self, codingPath: codingPath)
            }
            throw error
        }
    }

    @inline(__always)
    private func decodeUInt<T: UnsignedInteger>(key: K) throws -> T {
        let value = try getValue(forKey: key)
        do {
            return try decoder.unboxUInt(value, as: T.self)!
        } catch {
            if let error = error as? MsgPackDecodingError {
                throw error.asDecodingError(T.self, codingPath: codingPath)
            }
            throw error
        }
    }
}

internal protocol DataNumber {
    init(data: Data) throws
    var data: Data { get }
}

extension Float: DataNumber {
    init(data: Data) throws {
        self = .init(bitPattern: .init(try bigEndianUInt(data)))
    }

    var data: Data {
        withUnsafePointer(to: bitPattern.bigEndian) {
            Data(buffer: UnsafeBufferPointer(start: $0, count: 1))
        }
    }
}

extension Double: DataNumber {
    init(data: Data) throws {
        self = .init(bitPattern: .init(try bigEndianUInt(data)))
    }

    var data: Data {
        withUnsafePointer(to: bitPattern.bigEndian) {
            Data(buffer: UnsafeBufferPointer(start: $0, count: 1))
        }
    }
}

enum MsgPackDecodingError: Error {
    case dataCorrupted
}

extension MsgPackDecodingError {
    func asDecodingError<T>(_ type: T.Type, codingPath: [CodingKey]) -> DecodingError {
        switch self {
        case .dataCorrupted:
            let context = DecodingError.Context(codingPath: codingPath, debugDescription: "Expected to decode \(type) but it failed")
            return DecodingError.dataCorrupted(context)
        }
    }
}
