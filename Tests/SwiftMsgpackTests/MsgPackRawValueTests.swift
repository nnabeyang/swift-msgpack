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

private struct Envelope: Decodable, Equatable {
    let kind: String
    let payload: MsgPackRawValue
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
