import Foundation

enum Wire {
    static let version = 1
    static let relayCapability = "transport.relay"

    static func newId() -> String { UUID().uuidString.lowercased() }

    private static func envelope(_ type: String, _ payload: [String: Any], _ id: String) throws -> Data {
        let frame: [String: Any] = [
            "v": version,
            "id": id,
            "type": type,
            "timestamp": Int(Date().timeIntervalSince1970 * 1000),
            "payload": payload,
        ]
        return try JSONSerialization.data(withJSONObject: frame)
    }

    /// A frame the Server reads: it is sent as text.
    static func control(_ type: String, _ payload: [String: Any]) throws -> String {
        String(decoding: try envelope(type, payload, newId()), as: UTF8.self)
    }

    /// A message only the computer reads: it is encrypted before it is sent.
    static func message(_ type: String, _ payload: [String: Any], id: String) throws -> Data {
        try envelope(type, payload, id)
    }

    static func parse(_ data: Data) throws -> (type: String, payload: [String: Any]) {
        guard let frame = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              (frame["v"] as? Int) == version,
              let type = frame["type"] as? String,
              let payload = frame["payload"] as? [String: Any] else {
            throw LinkError("BAD_FRAME", "A frame from the link is invalid.")
        }
        return (type, payload)
    }

    /// Any JSON value as bytes; a missing value becomes `null`.
    static func json(_ value: Any?) -> Data {
        let object: Any = value ?? NSNull()
        return (try? JSONSerialization.data(withJSONObject: object, options: [.fragmentsAllowed])) ?? Data("null".utf8)
    }
}

/// Splits plaintext before Noise encryption and joins it after decryption.
/// One Noise transport message holds at most 65,535 bytes.
struct SecureMessageCodec {
    static let chunkBytes = 48 * 1024
    static let maxMessageBytes = 4 * 1024 * 1024
    private static let magic: [UInt8] = [0x44, 0x53, 0x42, 0x46] // DSBF
    private static let headerBytes = 17
    private static let maxInFlight = 8

    private struct Assembly {
        let total: Int
        let totalBytes: Int
        var chunks: [Data] = []
        var receivedBytes = 0
    }

    private var nextMessageId: UInt32 = 1
    private var assemblies: [UInt32: Assembly] = [:]

    mutating func encode(_ message: Data) throws -> [Data] {
        guard message.count <= Self.maxMessageBytes else {
            throw LinkError("MESSAGE_TOO_LARGE", "The message is too large to send.")
        }
        if message.count <= Self.chunkBytes { return [message] }
        let bytes = [UInt8](message)
        let messageId = nextMessageId
        nextMessageId = messageId == UInt32.max ? 1 : messageId + 1
        let total = (bytes.count + Self.chunkBytes - 1) / Self.chunkBytes
        var frames: [Data] = []
        for index in 0..<total {
            let start = index * Self.chunkBytes
            let end = min(bytes.count, start + Self.chunkBytes)
            var frame = Self.magic
            frame.append(1)
            frame.append(contentsOf: Self.be32(messageId))
            frame.append(contentsOf: Self.be16(UInt16(index)))
            frame.append(contentsOf: Self.be16(UInt16(total)))
            frame.append(contentsOf: Self.be32(UInt32(bytes.count)))
            frame.append(contentsOf: bytes[start..<end])
            frames.append(Data(frame))
        }
        return frames
    }

    /// Returns the whole message once its last piece has arrived.
    mutating func decode(_ frame: Data) throws -> Data? {
        let bytes = [UInt8](frame)
        guard bytes.count >= Self.magic.count, Array(bytes[0..<4]) == Self.magic else { return frame }
        let invalid = LinkError("BAD_FRAGMENT", "A piece of a long message is invalid.")
        guard bytes.count >= Self.headerBytes, bytes[4] == 1 else { throw invalid }
        let messageId = Self.read32(bytes, 5)
        let index = Int(Self.read16(bytes, 9))
        let total = Int(Self.read16(bytes, 11))
        let totalBytes = Int(Self.read32(bytes, 13))
        guard messageId != 0, total >= 2, index < total,
              totalBytes > Self.chunkBytes, totalBytes <= Self.maxMessageBytes,
              total == (totalBytes + Self.chunkBytes - 1) / Self.chunkBytes else { throw invalid }
        let expected = min(Self.chunkBytes, totalBytes - index * Self.chunkBytes)
        let chunk = Data(bytes[Self.headerBytes...])
        guard chunk.count == expected else { throw invalid }

        var assembly: Assembly
        if let existing = assemblies[messageId] {
            assembly = existing
        } else {
            guard index == 0, assemblies.count < Self.maxInFlight else { throw invalid }
            assembly = Assembly(total: total, totalBytes: totalBytes)
        }
        guard assembly.total == total, assembly.totalBytes == totalBytes, index == assembly.chunks.count else {
            assemblies[messageId] = nil
            throw invalid
        }
        assembly.chunks.append(chunk)
        assembly.receivedBytes += chunk.count
        if assembly.chunks.count < total {
            assemblies[messageId] = assembly
            return nil
        }
        assemblies[messageId] = nil
        guard assembly.receivedBytes == totalBytes else { throw invalid }
        var message = Data(capacity: totalBytes)
        for part in assembly.chunks { message.append(part) }
        return message
    }

    private static func be32(_ value: UInt32) -> [UInt8] {
        [UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)]
    }

    private static func be16(_ value: UInt16) -> [UInt8] {
        [UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)]
    }

    private static func read32(_ bytes: [UInt8], _ at: Int) -> UInt32 {
        UInt32(bytes[at]) << 24 | UInt32(bytes[at + 1]) << 16 | UInt32(bytes[at + 2]) << 8 | UInt32(bytes[at + 3])
    }

    private static func read16(_ bytes: [UInt8], _ at: Int) -> UInt16 {
        UInt16(bytes[at]) << 8 | UInt16(bytes[at + 1])
    }
}
