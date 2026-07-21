import XCTest
@testable import SwiftMsgpack

final class MsgPackRawValueTests: XCTestCase {
    private let eager = MsgPackDecoder()
    private let lazy = MsgPackDecoder(options: [.lazyScan])
    private let encoder = MsgPackEncoder()

    private func bothModes(_ body: (MsgPackDecoder, String) throws -> Void) rethrows {
        try body(eager, "eager")
        try body(lazy, "lazy")
    }

    // MARK: - Decoding

    func testDecodeTopLevelBool() throws {
        try bothModes { decoder, mode in
            let raw = try decoder.decode(MsgPackRawValue.self, from: Data(hex: "c3"))
            XCTAssertEqual(raw.data, Data([0xC3]), "mode: \(mode)")
        }
    }

    func testDecodeTopLevelMap() throws {
        try bothModes { decoder, mode in
            let bytes = Data(hex: "82a15812a15934")
            let raw = try decoder.decode(MsgPackRawValue.self, from: bytes)
            XCTAssertEqual(raw.data, bytes, "mode: \(mode)")
        }
    }

    func testDecodePayloadInEnvelopeForInt() throws {
        let bytes = Data(hex: "82a46b696e64a3666f6fa77061796c6f61642a")
        try bothModes { decoder, mode in
            let env = try decoder.decode(Envelope.self, from: bytes)
            XCTAssertEqual(env.kind, "foo", "mode: \(mode)")
            XCTAssertEqual(env.payload.data, Data([0x2A]), "mode: \(mode)")
        }
    }

    @available(iOS 17, *)
    func testDecodePayloadInEnvelopeForIntWithConfig() throws {
        let bytes = Data(hex: "82a46b696e64a3666f6fa77061796c6f61642a")
        try bothModes { decoder, mode in
            let env = try decoder.decode(Envelope.self, from: bytes, configuration: ())
            XCTAssertEqual(env.kind, "foo", "mode: \(mode)")
            XCTAssertEqual(env.payload.data, Data([0x2A]), "mode: \(mode)")
        }
    }

    func testDecodePayloadInEnvelopeViaSuperDecoder() throws {
        let bytes = Data(hex: "82a46b696e64a3666f6fa77061796c6f61642a")
        try bothModes { decoder, mode in
            let env = try decoder.decode(SuperDecoderEnvelope.self, from: bytes)
            XCTAssertEqual(env.kind, "foo", "mode: \(mode)")
            XCTAssertEqual(env.payload.data, Data([0x2A]), "mode: \(mode)")
        }
    }

    func testDecodePayloadInEnvelopeForString() throws {
        let payloadStr = try encoder.encode("hello")
        let bytes = try encoder.encode(["kind": "s", "payload": "hello"])
        try bothModes { decoder, mode in
            let env = try decoder.decode(Envelope.self, from: bytes)
            XCTAssertEqual(env.payload.data, payloadStr, "mode: \(mode)")
        }
    }

    func testDecodePayloadInEnvelopeForArray() throws {
        let payload = [1, 2, 3]
        let payloadBytes = try encoder.encode(payload)
        let bytes = try encoder.encode(EnvelopeOf(kind: "a", payload: payload))
        try bothModes { decoder, mode in
            let env = try decoder.decode(Envelope.self, from: bytes)
            XCTAssertEqual(env.payload.data, payloadBytes, "mode: \(mode)")
        }
    }

    func testDecodePayloadInEnvelopeForMap() throws {
        let payload: [String: Int] = ["x": 1, "y": 2]
        let payloadBytes = try encoder.encode(payload)
        let bytes = try encoder.encode(EnvelopeOf(kind: "m", payload: payload))
        try bothModes { decoder, mode in
            let env = try decoder.decode(Envelope.self, from: bytes)
            let inner = try decoder.decode([String: Int].self, from: env.payload.data)
            XCTAssertEqual(inner, payload, "mode: \(mode)")
            XCTAssertEqual(env.payload.data, payloadBytes, "mode: \(mode)")
        }
    }

    func testDecodePayloadInEnvelopeForExt() throws {
        let ts = MsgPackTimestamp(seconds: 1, nanoseconds: 0)
        let bytes = try encoder.encode(EnvelopeOf(kind: "t", payload: ts))
        let tsBytes = try encoder.encode(ts)
        try bothModes { decoder, mode in
            let env = try decoder.decode(Envelope.self, from: bytes)
            XCTAssertEqual(env.payload.data, tsBytes, "mode: \(mode)")
            let decoded = try decoder.decode(MsgPackTimestamp.self, from: env.payload.data)
            XCTAssertEqual(decoded, ts, "mode: \(mode)")
        }
    }

    func testDecodeArrayOfRawValues() throws {
        let bytes = Data(hex: "93c3c0a3666f6f")
        try bothModes { decoder, mode in
            let arr = try decoder.decode([MsgPackRawValue].self, from: bytes)
            XCTAssertEqual(arr.count, 3, "mode: \(mode)")
            XCTAssertEqual(arr[0].data, Data([0xC3]), "mode: \(mode)")
            XCTAssertEqual(arr[1].data, Data([0xC0]), "mode: \(mode)")
            XCTAssertEqual(arr[2].data, Data([0xA3, 0x66, 0x6F, 0x6F]), "mode: \(mode)")
        }
    }

    func testDecodeMapOfRawValues() throws {
        let bytes = Data(hex: "81a16bc3")
        try bothModes { decoder, mode in
            let dict = try decoder.decode([String: MsgPackRawValue].self, from: bytes)
            XCTAssertEqual(dict["k"]?.data, Data([0xC3]), "mode: \(mode)")
        }
    }

    func testDecodeAdjacentHeterogeneousRawValuesPreservesExactRanges() throws {
        let bytes = Data(hex: "952ad903666f6fc40300ff7f92c381a16bc081a17893010203")
        let expected = [
            Data(hex: "2a"),
            Data(hex: "d903666f6f"),
            Data(hex: "c40300ff7f"),
            Data(hex: "92c381a16bc0"),
            Data(hex: "81a17893010203"),
        ]

        try bothModes { decoder, mode in
            let values = try decoder.decode([MsgPackRawValue].self, from: bytes)
            XCTAssertEqual(values.map(\.data), expected, "mode: \(mode)")
        }
    }

    func testDecodeRawValuesAfterLazyMapReverseLookupPreservesExactRanges() throws {
        let bytes = Data(hex: "82a161d9036f6e65a16292c3c0")

        try bothModes { decoder, mode in
            let value = try decoder.decode(ReverseRawEnvelope.self, from: bytes)
            XCTAssertEqual(value.a.data, Data(hex: "d9036f6e65"), "mode: \(mode)")
            XCTAssertEqual(value.b.data, Data(hex: "92c3c0"), "mode: \(mode)")
        }
    }

    // Foundation's DecodableWithConfiguration conformances for Array/Optional call the
    // element's init directly as `T(from: superDecoder(), configuration:)`, bypassing the
    // special casing in _MsgPackDecoder.unwrap(as:). Verifies that init(from:) itself can
    // handle a _MsgPackDecoder.
    @available(iOS 17, *)
    func testDecodeArrayOfRawValuesWithConfig() throws {
        let bytes = Data(hex: "93c3c0a3666f6f")
        try bothModes { decoder, mode in
            let arr = try decoder.decode([MsgPackRawValue].self, from: bytes, configuration: ())
            XCTAssertEqual(arr.count, 3, "mode: \(mode)")
            XCTAssertEqual(arr[0].data, Data([0xC3]), "mode: \(mode)")
            XCTAssertEqual(arr[1].data, Data([0xC0]), "mode: \(mode)")
            XCTAssertEqual(arr[2].data, Data([0xA3, 0x66, 0x6F, 0x6F]), "mode: \(mode)")
        }
    }

    @available(iOS 17, *)
    func testDecodeOptionalArrayOfRawValuesWithConfig() throws {
        let bytes = Data(hex: "93c3c0a3666f6f")
        try bothModes { decoder, mode in
            let arr = try decoder.decode([MsgPackRawValue]?.self, from: bytes, configuration: ())
            XCTAssertEqual(arr?.count, 3, "mode: \(mode)")
            XCTAssertEqual(arr?[0].data, Data([0xC3]), "mode: \(mode)")
        }
    }

    func testDecodeWithForeignDecoderFails() {
        XCTAssertThrowsError(try JSONDecoder().decode(MsgPackRawValue.self, from: Data("42".utf8))) { error in
            guard case DecodingError.dataCorrupted = error else {
                XCTFail("expected DecodingError.dataCorrupted, got \(error)")
                return
            }
        }
    }

    // MARK: - Encoding

    func testEncodeTopLevel() throws {
        let raw = MsgPackRawValue(Data([0xC3]))
        let bytes = try encoder.encode(raw)
        XCTAssertEqual(bytes, Data([0xC3]))
    }

    func testEncodeKeyed() throws {
        let payload = Data([0x2A])
        let env = EnvelopeOf(kind: "foo", payload: MsgPackRawValue(payload))
        let bytes = try encoder.encode(env)
        let env2 = try eager.decode(Envelope.self, from: bytes)
        XCTAssertEqual(env2.kind, "foo")
        XCTAssertEqual(env2.payload.data, payload)
    }

    func testEncodeArray() throws {
        let arr = [MsgPackRawValue(Data([0xC3])), MsgPackRawValue(Data([0xC2]))]
        let bytes = try encoder.encode(arr)
        XCTAssertEqual(bytes, Data([0x92, 0xC3, 0xC2]))
    }

    func testEncodeEmptyDataRejected() {
        XCTAssertThrowsError(try encoder.encode(MsgPackRawValue(Data()))) { error in
            guard case EncodingError.invalidValue = error else {
                XCTFail("expected EncodingError.invalidValue, got \(error)")
                return
            }
        }
    }

    // Encoding through superEncoder() calls encode(to:) directly, bypassing the special
    // casing in wrapEncodable. Verifies that encode(to:) itself can handle a _MsgPackEncoder.
    func testEncodeViaSuperEncoder() throws {
        let payload = Data([0x2A])
        let env = SuperEncoderEnvelope(kind: "foo", payload: MsgPackRawValue(payload))
        let bytes = try encoder.encode(env)
        let env2 = try eager.decode(Envelope.self, from: bytes)
        XCTAssertEqual(env2.kind, "foo")
        XCTAssertEqual(env2.payload.data, payload)
    }

    func testEncodeEmptyDataViaSuperEncoderRejected() {
        let env = SuperEncoderEnvelope(kind: "foo", payload: MsgPackRawValue(Data()))
        XCTAssertThrowsError(try encoder.encode(env)) { error in
            guard case EncodingError.invalidValue = error else {
                XCTFail("expected EncodingError.invalidValue, got \(error)")
                return
            }
        }
    }

    func testEncodeWithForeignEncoderFails() {
        let env = EnvelopeOf(kind: "foo", payload: MsgPackRawValue(Data([0x2A])))
        XCTAssertThrowsError(try JSONEncoder().encode(env)) { error in
            guard case EncodingError.invalidValue = error else {
                XCTFail("expected EncodingError.invalidValue, got \(error)")
                return
            }
        }
    }

    // MARK: - Round trip

    func testRoundTripInjectedPayload() throws {
        let original = SamplePayload(n: 7, label: "lucky")
        let prePayload = try encoder.encode(original)
        let env = EnvelopeOf(kind: "sample", payload: MsgPackRawValue(prePayload))
        let envBytes = try encoder.encode(env)

        try bothModes { decoder, mode in
            let envBack = try decoder.decode(Envelope.self, from: envBytes)
            XCTAssertEqual(envBack.kind, "sample", "mode: \(mode)")
            let payloadBack = try decoder.decode(SamplePayload.self, from: envBack.payload.data)
            XCTAssertEqual(payloadBack, original, "mode: \(mode)")
        }
    }
}

private struct ReverseRawEnvelope: Decodable {
    let a: MsgPackRawValue
    let b: MsgPackRawValue

    enum CodingKeys: String, CodingKey {
        case a
        case b
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        b = try container.decode(MsgPackRawValue.self, forKey: .b)
        a = try container.decode(MsgPackRawValue.self, forKey: .a)
    }
}

private struct Envelope: Decodable, DecodableWithConfiguration, Equatable {
    typealias DecodingConfiguration = Void
    let kind: String
    let payload: MsgPackRawValue

    init(from decoder: any Decoder, configuration _: DecodingConfiguration) throws {
        try self.init(from: decoder)
    }
}

// Conformance added in the test target to reach Foundation's Array/Optional
// DecodableWithConfiguration conformances, which call init(from:) on each element directly.
extension MsgPackRawValue: DecodableWithConfiguration {
    public typealias DecodingConfiguration = Void

    public init(from decoder: any Decoder, configuration _: Void) throws {
        try self.init(from: decoder)
    }
}

private struct SuperDecoderEnvelope: Decodable {
    let kind: String
    let payload: MsgPackRawValue

    private enum CodingKeys: String, CodingKey {
        case kind
        case payload
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(String.self, forKey: .kind)
        payload = try MsgPackRawValue(from: container.superDecoder(forKey: .payload))
    }
}

private struct SuperEncoderEnvelope: Encodable {
    let kind: String
    let payload: MsgPackRawValue

    private enum CodingKeys: String, CodingKey {
        case kind
        case payload
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try payload.encode(to: container.superEncoder(forKey: .payload))
    }
}

private struct EnvelopeOf<Payload: Encodable>: Encodable {
    let kind: String
    let payload: Payload
}

private struct SamplePayload: Codable, Equatable {
    let n: Int
    let label: String
}

private extension Unicode.Scalar {
    var hexNibble: UInt8 {
        let value = value
        if value >= 48, value <= 57 {
            return UInt8(value - 48)
        } else if value >= 65, value <= 70 {
            return UInt8(value - 55)
        } else if value >= 97, value <= 102 {
            return UInt8(value - 87)
        }
        fatalError("\(self) not a legal hex nibble")
    }
}

private extension Data {
    init(hex: String) {
        let scalars = hex.unicodeScalars
        var bytes = [UInt8](repeating: 0, count: (scalars.count + 1) >> 1)
        for (index, scalar) in scalars.enumerated() {
            var nibble = scalar.hexNibble
            if index & 1 == 0 {
                nibble <<= 4
            }
            bytes[index >> 1] |= nibble
        }
        self = Data(bytes)
    }
}
