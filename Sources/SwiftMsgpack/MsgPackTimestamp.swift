import Foundation

public struct MsgPackTimestamp: Equatable {
    public var seconds: UInt64
    public var nanoseconds: UInt32
    enum CodingKeys: CodingKey {
        case seconds
        case nanoseconds
    }

    public init(seconds: UInt64, nanoseconds: UInt32) {
        self.seconds = seconds
        self.nanoseconds = nanoseconds
    }
}

extension MsgPackTimestamp: MsgPackCodable {
    public init(msgPack data: Data) throws {
        let n = data.count
        switch n {
        case 4: // timestamp 32 bit
            seconds = UInt64(UInt32(bigEndian: data.withUnsafeBytes { $0.baseAddress?.assumingMemoryBound(to: UInt32.self).pointee ?? 0 }))
            nanoseconds = 0
        case 8: // timestamp 64 bit
            let number = UInt64(bigEndian: data.withUnsafeBytes { $0.baseAddress?.assumingMemoryBound(to: UInt64.self).pointee ?? 0 })
            seconds = UInt64(number & (1 << 34 - 1))
            nanoseconds = UInt32(number >> 34)
        case 12: // timestamp 96 bit
            seconds = UInt64(bigEndian: data.dropFirst(4).withUnsafeBytes { $0.baseAddress?.assumingMemoryBound(to: UInt64.self).pointee ?? 0 })
            nanoseconds = UInt32(bigEndian: data.dropLast(8).withUnsafeBytes { $0.baseAddress?.assumingMemoryBound(to: UInt32.self).pointee ?? 0 })
        default:
            throw MsgPackDecodingError.dataCorrupted
        }
    }

    public var type: Int8 { -1 }
    public func encodeMsgPack() throws -> Data {
        if seconds >> 34 == 0 {
            if nanoseconds == 0 { // timestamp 32 bit
                let v: UInt32 = .init(seconds)
                return withUnsafePointer(to: v.bigEndian) {
                    Data(buffer: UnsafeBufferPointer(start: $0, count: 1))
                }
            }
            // timestamp 64 bit
            let data: UInt64 = .init(nanoseconds) << 34 | seconds
            return withUnsafePointer(to: data.bigEndian) {
                Data(buffer: UnsafeBufferPointer(start: $0, count: 1))
            }
        }
        var bb: Data = .init(capacity: 12)
        bb.append(withUnsafePointer(to: UInt32(nanoseconds).bigEndian) {
            Data(buffer: UnsafeBufferPointer(start: $0, count: 1))
        })
        bb.append(withUnsafePointer(to: UInt64(seconds).bigEndian) {
            Data(buffer: UnsafeBufferPointer(start: $0, count: 1))
        })
        return bb
    }
}
