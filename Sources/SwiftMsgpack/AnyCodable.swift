import Foundation

@inline(never)
@usableFromInline
internal func _abstract(
    file: StaticString = #file,
    line: UInt = #line
) -> Never {
    fatalError("Method must be overridden", file: file, line: line)
}

public struct AnyCodable {
    internal enum BoxType {
        case encodable(_AnyBaseBox)
        case equatable(_AnyEquatableBox)
        case hashable(_AnyHashableBox)

        var encodable: _AnyBaseBox {
            switch self {
            case let .encodable(box): return box
            case let .equatable(box): return box
            case let .hashable(box): return box
            }
        }

        var equatable: _AnyEquatableBox? {
            switch self {
            case .encodable: return nil
            case let .equatable(box): return box
            case let .hashable(box): return box
            }
        }

        var base: Any {
            switch self {
            case let .encodable(box): return box._base
            case let .equatable(box): return box._base
            case let .hashable(box): return box._base
            }
        }
    }

    var _box: BoxType

    init(encodable box: _AnyBaseBox) {
        _box = .encodable(box)
    }

    init(equatable box: _AnyEquatableBox) {
        _box = .equatable(box)
    }

    init(hashable box: _AnyHashableBox) {
        _box = .hashable(box)
    }

    public init<T: Encodable>(_ base: T) {
        self.init(encodable: _ConcreateCodableBox(base))
    }

    public init<T: Encodable & Equatable>(_ base: T) {
        self.init(equatable: _ConcreateCodableBox(base))
    }

    public init<T: Encodable & Hashable>(_ base: T) {
        self.init(hashable: _ConcreateCodableBox(base))
    }

    public var base: Any {
        _box.base
    }
}

extension AnyCodable: Equatable {
    public static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        guard let lhs = lhs._box.equatable else {
            return false
        }
        guard let rhs = rhs._box.equatable else {
            return false
        }
        return lhs._isEqual(to: rhs) ?? false
    }
}

extension AnyCodable: Hashable {
    public func hash(into hasher: inout Hasher) {
        if case let .hashable(box) = _box {
            box._hash(into: &hasher)
            return
        }
        _abstract()
    }
}

extension AnyCodable: Encodable {
    public func encode(to encoder: Encoder) throws {
        try _box.encodable._encode(to: encoder)
    }
}

extension AnyCodable: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self.init(Self?.none)
            return
        }

        if let bool = try? container.decode(Bool.self) {
            self.init(bool)
            return
        }
        if let int = try? container.decode(Int.self) {
            self.init(int)
            return
        }
        if let uint = try? container.decode(UInt.self) {
            self.init(uint)
            return
        }
        if let string = try? container.decode(String.self) {
            self.init(string)
            return
        }
        if let float = try? container.decode(Double.self) {
            self.init(float)
            return
        }
        if let data = try? container.decode(Data.self) {
            self.init(data)
            return
        }
        if let dictionary = try? container.decode([AnyCodable: AnyCodable].self) {
            self.init(dictionary)
            return
        }
        if let array = try? container.decode([AnyCodable].self) {
            self.init(array)
            return
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "AnyCodable value cannot be decoded")
    }
}

extension AnyCodable: CustomDebugStringConvertible {
    public var debugDescription: String {
        guard let base = base as? CustomDebugStringConvertible else {
            return "AnyCodable(\(base))"
        }
        return "AnyCodable(\(base.debugDescription))"
    }
}

internal struct _ConcreateCodableBox<Base> {
    var _baseCodableKey: Base
    init(_ base: Base) {
        _baseCodableKey = base
    }

    var _base: Any {
        _baseCodableKey
    }
}

internal protocol _AnyBaseBox {
    func _encode(to encoder: Encoder) throws
    var _base: Any { get }
}

extension _ConcreateCodableBox: _AnyBaseBox where Base: Encodable {
    func _encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(_baseCodableKey)
    }
}

internal protocol _AnyEquatableBox: _AnyBaseBox {
    func _isEqual(to box: _AnyEquatableBox) -> Bool?
    func _unbox<T: Encodable & Equatable>() -> T?
}

extension _ConcreateCodableBox: _AnyEquatableBox where Base: Encodable & Equatable {
    func _unbox<T: Encodable & Equatable>() -> T? {
        (self as _AnyEquatableBox as? _ConcreateCodableBox<T>)?._baseCodableKey
    }

    func _isEqual(to rhs: _AnyEquatableBox) -> Bool? {
        if let rhs: Base = rhs._unbox() {
            return _baseCodableKey == rhs
        }
        return nil
    }
}

internal protocol _AnyHashableBox: _AnyEquatableBox {
    func _hash(into hasher: inout Hasher)
}

extension _ConcreateCodableBox: _AnyHashableBox where Base: Encodable & Hashable {
    func _hash(into hasher: inout Hasher) {
        _baseCodableKey.hash(into: &hasher)
    }
}
