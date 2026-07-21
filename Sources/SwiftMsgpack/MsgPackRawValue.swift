import Foundation

public struct MsgPackRawValue: Hashable, Sendable {
    public let data: Data

    public init(_ data: Data) {
        self.data = data
    }
}

extension MsgPackRawValue: Codable {
    public init(from decoder: Decoder) throws {
        if let decoder = decoder as? _MsgPackDecoder {
            self = try decoder.unwrap(as: Self.self)
            return
        }
        throw DecodingError.dataCorrupted(
            .init(
                codingPath: decoder.codingPath,
                debugDescription: "MsgPackRawValue can only be decoded via MsgPackDecoder."
            ))
    }

    public func encode(to encoder: Encoder) throws {
        if let encoder = encoder as? _MsgPackEncoder {
            try encoder.fill(rawValue: self)
            return
        }
        throw EncodingError.invalidValue(
            self,
            .init(
                codingPath: encoder.codingPath,
                debugDescription: "MsgPackRawValue can only be encoded via MsgPackEncoder."
            ))
    }
}
