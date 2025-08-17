import Foundation

private protocol _MsgPackDictionaryDecodableMarker {}

extension Dictionary: _MsgPackDictionaryDecodableMarker where Key: Encodable, Value: Decodable {}

private protocol _MsgPackArrayDecodableMarker {}

extension Array: _MsgPackArrayDecodableMarker where Element: Decodable {}

open class MsgPackDecoder {
    public init() {}
    open func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try data.withUnsafeBytes {
            let scanner: MsgPackScanner = .init(ptr: $0.baseAddress!, count: $0.count)
            let value = scanner.scan()
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
}

public protocol MsgPackDecodable: Decodable {
    var type: Int8 { get }
    init(msgPack data: Data) throws
}

public typealias MsgPackCodable = MsgPackDecodable & MsgPackEncodable

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
            throw DecodingError.typeMismatch([String: Any].self, DecodingError.Context(
                codingPath: codingPath,
                debugDescription: "Expected to decode \([String: Any].self) but found \(value.debugDataTypeDescription) instead."
            ))
        }
        return KeyedDecodingContainer(MsgPackKeyedDecodingContainer<Key>(referencing: self, container: value))
    }

    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        switch value {
        case .array, .map, .none: break
        default:
            throw DecodingError.typeMismatch([Any].self, DecodingError.Context(
                codingPath: codingPath,
                debugDescription: "Expected to decode \([Any].self) but found \(value.debugDataTypeDescription) instead."
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
        if case let .literal(value) = value {
            switch value {
            case let .bool(v): return v
            case .nil: return nil
            default:
                break
            }
        }

        throw DecodingError.typeMismatch(type, DecodingError.Context(
            codingPath: codingPath,
            debugDescription: "Expected to decode \(type) but found \(value.debugDataTypeDescription) instead."
        ))
    }

    func unbox(_ value: MsgPackValue, as type: String.Type) throws -> String? {
        if case let .literal(value) = value {
            switch value {
            case let .str(v):
                return String._tryFromUTF8(v)
            case .nil:
                return nil
            default:
                break
            }
        }

        throw DecodingError.typeMismatch(type, DecodingError.Context(
            codingPath: codingPath,
            debugDescription: "Expected to decode \(type) but found \(value.debugDataTypeDescription) instead."
        ))
    }

    func unboxFloat32(_ value: MsgPackValue) throws -> Float? {
        if case let .literal(f) = value {
            switch f {
            case let .float32(v):
                return v
            case let .float64(v):
                return Float(v)
            case .nil:
                return nil
            default:
                break
            }
        }

        throw DecodingError.typeMismatch(Float.self, DecodingError.Context(
            codingPath: codingPath,
            debugDescription: "Expected to decode \(Float.self) but found \(value.debugDataTypeDescription) instead."
        ))
    }

    func unboxFloat64(_ value: MsgPackValue) throws -> Double? {
        if case let .literal(f) = value {
            switch f {
            case let .float32(v):
                return Double(v)
            case let .float64(v):
                return v
            case .nil:
                return nil
            default:
                break
            }
        }

        throw DecodingError.typeMismatch(Double.self, DecodingError.Context(
            codingPath: codingPath,
            debugDescription: "Expected to decode \(Double.self) but found \(value.debugDataTypeDescription) instead."
        ))
    }

    func unboxInt<T: SignedInteger & FixedWidthInteger>(_ value: MsgPackValue) throws -> T {
        if case let .literal(vv) = value {
            switch vv {
            case let .uint(v), let .int(v):
                return T(truncatingIfNeeded: v)
            default:
                break
            }
        }

        throw DecodingError.typeMismatch(Int8.self, DecodingError.Context(
            codingPath: codingPath,
            debugDescription: "Expected to decode \(T.self) but found \(value.debugDataTypeDescription) instead."
        ))
    }

    func unboxUInt<T: UnsignedInteger & FixedWidthInteger>(_ value: MsgPackValue) throws -> T {
        if case let .literal(literal) = value {
            switch literal {
            case let .uint(v):
                return T(truncatingIfNeeded: v)
            default:
                break
            }
        }

        throw DecodingError.typeMismatch(UInt.self, DecodingError.Context(
            codingPath: codingPath,
            debugDescription: "Expected to decode \(T.self) but found \(value.debugDataTypeDescription) instead."
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
            return value as! T
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
        switch value {
        case let .literal(.bin(v)):
            v
        case let .literal(.str(v)):
            .init(buffer: v)
        default:
            throw DecodingError.typeMismatch(Data.self, DecodingError.Context(codingPath: codingPath, debugDescription: ""))
        }
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
            throw DecodingError.typeMismatch(T.self, DecodingError.Context(
                codingPath: codingPath,
                debugDescription: "Expected to decode \(T.self) but found \(value.debugDataTypeDescription) instead."
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
        if case .literal(.nil) = value {
            return true
        } else {
            return false
        }
    }

    func decode(_: Bool.Type) throws -> Bool {
        try decoder.unbox(value, as: Bool.self)!
    }

    func decode(_ type: String.Type) throws -> String {
        try decoder.unbox(value, as: type)!
    }

    func decode(_: Double.Type) throws -> Double {
        try decoder.unboxFloat64(value)!
    }

    func decode(_: Float.Type) throws -> Float {
        try decoder.unboxFloat32(value)!
    }

    func decode(_: Int.Type) throws -> Int {
        try decoder.unboxInt(value)
    }

    func decode(_: Int8.Type) throws -> Int8 {
        try decoder.unboxInt(value)
    }

    func decode(_: Int16.Type) throws -> Int16 {
        try decoder.unboxInt(value)
    }

    func decode(_: Int32.Type) throws -> Int32 {
        try decoder.unboxInt(value)
    }

    func decode(_: Int64.Type) throws -> Int64 {
        try decoder.unboxInt(value)
    }

    @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
    func decode(_: Int128.Type) throws -> Int128 {
        try decoder.unboxInt(value)
    }

    func decode(_: UInt.Type) throws -> UInt {
        try decoder.unboxUInt(value)
    }

    func decode(_: UInt8.Type) throws -> UInt8 {
        try decoder.unboxUInt(value)
    }

    func decode(_: UInt16.Type) throws -> UInt16 {
        try decoder.unboxUInt(value)
    }

    func decode(_: UInt32.Type) throws -> UInt32 {
        try decoder.unboxUInt(value)
    }

    func decode(_: UInt64.Type) throws -> UInt64 {
        try decoder.unboxUInt(value)
    }

    @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
    func decode(_: UInt128.Type) throws -> UInt128 {
        try decoder.unboxUInt(value)
    }

    func decode<T>(_ type: T.Type) throws -> T where T: Decodable {
        try decoder.unwrap(as: type)
    }
}

private struct MsgPackUnkeyedUnkeyedDecodingContainer: UnkeyedDecodingContainer {
    private let decoder: _MsgPackDecoder
    private(set) var codingPath: [CodingKey]
    public private(set) var currentIndex: Int
    private var container: [MsgPackValue]

    init(referencing decoder: _MsgPackDecoder, container: MsgPackValue) {
        self.decoder = decoder
        codingPath = decoder.codingPath
        currentIndex = 0
        self.container = container.asArray()
    }

    var count: Int? {
        container.count
    }

    var isAtEnd: Bool {
        currentIndex >= count!
    }

    mutating func decodeNil() throws -> Bool {
        let value = try getNextValue(ofType: Never.self)
        if case .literal(.nil) = value {
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
        return try decoder.unbox(value, as: Bool.self)!
    }

    mutating func decode(_: String.Type) throws -> String {
        let value = try getNextValue(ofType: String.self)
        currentIndex += 1
        return try decoder.unbox(value, as: String.self)!
    }

    mutating func decode(_: Double.Type) throws -> Double {
        try decodeFloat64()
    }

    mutating func decode(_: Float.Type) throws -> Float {
        try decodeFloat32()
    }

    mutating func decode(_: Int.Type) throws -> Int {
        try decodeInt()
    }

    mutating func decode(_: Int8.Type) throws -> Int8 {
        try decodeInt()
    }

    mutating func decode(_: Int16.Type) throws -> Int16 {
        try decodeInt()
    }

    mutating func decode(_: Int32.Type) throws -> Int32 {
        try decodeInt()
    }

    mutating func decode(_: Int64.Type) throws -> Int64 {
        try decodeInt()
    }

    @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
    mutating func decode(_: Int128.Type) throws -> Int128 {
        try decodeInt()
    }

    mutating func decode(_: UInt.Type) throws -> UInt {
        try decodeUInt()
    }

    mutating func decode(_: UInt8.Type) throws -> UInt8 {
        try decodeUInt()
    }

    mutating func decode(_: UInt16.Type) throws -> UInt16 {
        try decodeUInt()
    }

    mutating func decode(_: UInt32.Type) throws -> UInt32 {
        try decodeUInt()
    }

    mutating func decode64(_: UInt64.Type) throws -> UInt64 {
        try decodeUInt()
    }

    @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
    mutating func decode(_: UInt128.Type) throws -> UInt128 {
        try decodeUInt()
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
    private mutating func decodeUInt<T: UnsignedInteger & FixedWidthInteger>() throws -> T {
        defer {
            currentIndex += 1
        }
        let value = try getNextValue(ofType: T.self)
        return try decoder.unboxUInt(value)
    }

    @inline(__always)
    private mutating func decodeInt<T: SignedInteger & FixedWidthInteger>() throws -> T {
        defer {
            currentIndex += 1
        }
        let value = try getNextValue(ofType: T.self)
        return try decoder.unboxInt(value)
    }

    @inline(__always)
    private mutating func decodeFloat32() throws -> Float {
        let value = try getNextValue(ofType: Float.self)
        let result = try decoder.unboxFloat32(value)!
        currentIndex += 1
        return result
    }

    @inline(__always)
    private mutating func decodeFloat64() throws -> Double {
        let value = try getNextValue(ofType: Double.self)
        let result = try decoder.unboxFloat64(value)!
        currentIndex += 1
        return result
    }
}

private struct MsgPackKeyedDecodingContainer<K: CodingKey>: KeyedDecodingContainerProtocol {
    typealias Key = K

    private let decoder: _MsgPackDecoder
    private(set) var codingPath: [CodingKey]
    private var container: [String: MsgPackValue]

    static func asDictionary(value msgPackValue: MsgPackValue, using decoder: _MsgPackDecoder) -> [String: MsgPackValue] {
        var result = [String: MsgPackValue]()
        let a = msgPackValue.asDictionary()
        result.reserveCapacity(a.count)
        for (keyvalue, value) in a {
            guard let key = try? decoder.unbox(keyvalue, as: String.self) else {
                continue
            }
            result[key]._setIfNil(to: value)
        }

        return result
    }

    init(referencing decoder: _MsgPackDecoder, container: MsgPackValue) {
        self.decoder = decoder
        self.container = Self.asDictionary(value: container, using: decoder)
        codingPath = decoder.codingPath
    }

    var allKeys: [Key] {
        container.keys.compactMap {
            Key(stringValue: $0)
        }
    }

    func contains(_ key: Key) -> Bool {
        container[key.stringValue] != nil
    }

    func decodeNil(forKey key: Key) throws -> Bool {
        let value = try getValue(forKey: key)
        if case .literal(.nil) = value {
            return true
        } else {
            return false
        }
    }

    func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool {
        let value = try getValue(forKey: key)
        return try decoder.unbox(value, as: type)!
    }

    func decode(_ type: String.Type, forKey key: Key) throws -> String {
        let value = try getValue(forKey: key)
        return try decoder.unbox(value, as: type)!
    }

    func decode(_: Double.Type, forKey key: Key) throws -> Double {
        try decodeFloat64(key: key)
    }

    func decode(_: Float.Type, forKey key: Key) throws -> Float {
        try decodeFloat32(key: key)
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

    @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
    func decode(_: Int128.Type, forKey key: Key) throws -> Int128 {
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

    @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
    func decode(_: UInt128.Type, forKey key: Key) throws -> UInt128 {
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
        guard let value = container[key.stringValue] else {
            let context = DecodingError.Context(codingPath: codingPath, debugDescription: "No value assosiated with key \(key) (\"\(key.stringValue)\"")
            throw DecodingError.keyNotFound(key, context)
        }
        return value
    }

    @inline(__always)
    private func decodeFloat32(key: K) throws -> Float {
        let value = try getValue(forKey: key)
        return try decoder.unboxFloat32(value)!
    }

    @inline(__always)
    private func decodeFloat64(key: K) throws -> Double {
        let value = try getValue(forKey: key)
        return try decoder.unboxFloat64(value)!
    }

    @inline(__always)
    private func decodeInt<T: SignedInteger & FixedWidthInteger>(key: K) throws -> T {
        let value = try getValue(forKey: key)
        do {
            return try decoder.unboxInt(value)
        } catch {
            if let error = error as? MsgPackDecodingError {
                throw error.asDecodingError(T.self, codingPath: codingPath)
            }
            throw error
        }
    }

    @inline(__always)
    private func decodeUInt<T: UnsignedInteger & FixedWidthInteger>(key: K) throws -> T {
        let value = try getValue(forKey: key)
        do {
            return try decoder.unboxUInt(value)
        } catch {
            if let error = error as? MsgPackDecodingError {
                throw error.asDecodingError(T.self, codingPath: codingPath)
            }
            throw error
        }
    }
}

protocol DataNumber {
    var bytes: [UInt8] { get }
}

extension Float: DataNumber {
    var bytes: [UInt8] {
        withUnsafeBytes(of: bitPattern.bigEndian) {
            Array($0)
        }
    }
}

extension Double: DataNumber {
    var bytes: [UInt8] {
        withUnsafeBytes(of: bitPattern.bigEndian) {
            Array($0)
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

private extension Optional {
    mutating func _setIfNil(to value: Wrapped) {
        guard _fastPath(self == nil) else { return }
        self = value
    }
}
