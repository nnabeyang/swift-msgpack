import XCTest
@testable import SwiftMsgpack

final class EncodeStr8UnsupportTests: XCTestCase {
    private let encoder = MsgPackEncoder(options: [])

    private func t<X: Encodable>(in input: X, type _: X.Type, out: String) throws {
        let actual = try encoder.encode(input)
        XCTAssertEqual(actual.hexDescription, out)
    }

    func testEncode() throws {
        do {
            try t(in: "Hello", type: String.self, out: "a548656c6c6f")
            try t(in: "abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz", type: String.self, out: "da00686162636465666768696a6b6c6d6e6f707172737475767778797a6162636465666768696a6b6c6d6e6f707172737475767778797a6162636465666768696a6b6c6d6e6f707172737475767778797a6162636465666768696a6b6c6d6e6f707172737475767778797a")
            try t(in: Data("abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz".utf8), type: Data.self, out: "da00686162636465666768696a6b6c6d6e6f707172737475767778797a6162636465666768696a6b6c6d6e6f707172737475767778797a6162636465666768696a6b6c6d6e6f707172737475767778797a6162636465666768696a6b6c6d6e6f707172737475767778797a")
        } catch {
            XCTFail(error.localizedDescription)
        }
    }
}
