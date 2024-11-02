import XCTest
@testable import SwiftMsgpack

final class EncodeStr8UnsupportTests: XCTestCase {
    private let encoder = MsgPackEncoder(options: [])

    private func t<X: Encodable>(in input: X, type _: X.Type, out: String, file: StaticString = #filePath, line: UInt = #line) {
        do {
            let actual = try encoder.encode(input)
            XCTAssertEqual(actual.hexDescription, out, file: file, line: line)
        } catch {
            XCTFail("unexpected error: \(error)", file: file, line: line)
        }
    }

    func testEncode() {
        t(in: "Hello", type: String.self, out: "a548656c6c6f")
        t(in: "abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz", type: String.self, out: "da00686162636465666768696a6b6c6d6e6f707172737475767778797a6162636465666768696a6b6c6d6e6f707172737475767778797a6162636465666768696a6b6c6d6e6f707172737475767778797a6162636465666768696a6b6c6d6e6f707172737475767778797a")
        t(in: Data("abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz".utf8), type: Data.self, out: "da00686162636465666768696a6b6c6d6e6f707172737475767778797a6162636465666768696a6b6c6d6e6f707172737475767778797a6162636465666768696a6b6c6d6e6f707172737475767778797a6162636465666768696a6b6c6d6e6f707172737475767778797a")
    }
}
