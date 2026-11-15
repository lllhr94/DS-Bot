import CryptoKit
import Foundation

/// The phone's side of Noise_IK_25519_ChaChaPoly_SHA256: it starts the handshake
/// and already knows the computer's static key from pairing.
final class NoiseIKInitiator {
    private typealias PrivateKey = Curve25519.KeyAgreement.PrivateKey
    private typealias PublicKey = Curve25519.KeyAgreement.PublicKey

    private var h: Data
    private var ck: Data
    private var k: SymmetricKey?
    private var n: UInt64 = 0
    private let s: PrivateKey
    private let rs: PublicKey
    private let e: PrivateKey
    private var sendKey: SymmetricKey?
    private var receiveKey: SymmetricKey?
    private var sendCounter: UInt64 = 0
    private var receiveCounter: UInt64 = 0

    var complete: Bool { sendKey != nil }

    init(localPrivateKey: Data, remotePublicKey: Data, prologue: Data) throws {
        guard localPrivateKey.count == 32, remotePublicKey.count == 32 else {
            throw LinkError("INVALID_KEY", "X25519 keys must be 32 bytes.")
        }
        s = try PrivateKey(rawRepresentation: localPrivateKey)
        rs = try PublicKey(rawRepresentation: remotePublicKey)
        e = PrivateKey()
        let name = Data("Noise_IK_25519_ChaChaPoly_SHA256".utf8)
        h = name.count <= 32 ? name + Data(repeating: 0, count: 32 - name.count) : Data(SHA256.hash(data: name))
        ck = h
        mixHash(prologue)
        // IK: the responder's static key is known before the first message.
        mixHash(rs.rawRepresentation)
    }

    /// -> e, es, s, ss
    func writeFirstMessage(payload: Data) throws -> Data {
        var out = Data()
        let ephemeral = e.publicKey.rawRepresentation
        out.append(ephemeral)
        mixHash(ephemeral)
        mixKey(try Self.dh(e, rs))
        out.append(try encryptAndHash(s.publicKey.rawRepresentation))
        mixKey(try Self.dh(s, rs))
        out.append(try encryptAndHash(payload))
        return out
    }

    /// <- e, ee, se
    func readSecondMessage(_ message: Data) throws -> Data {
        guard message.count >= 32 + 16 else { throw LinkError("HANDSHAKE_FAILED", "The computer's handshake reply is too short.") }
        let remoteEphemeral = Data(message.prefix(32))
        let re = try PublicKey(rawRepresentation: remoteEphemeral)
        mixHash(remoteEphemeral)
        mixKey(try Self.dh(e, re))
        mixKey(try Self.dh(s, re))
        let payload = try decryptAndHash(Data(message.dropFirst(32)))
        let (first, second) = Self.hkdf(ck, Data())
        sendKey = SymmetricKey(data: first)
        receiveKey = SymmetricKey(data: second)
        return payload
    }

    func encrypt(_ plaintext: Data) throws -> Data {
        guard let sendKey else { throw LinkError("NOISE_NOT_READY", "The secure handshake is not complete.") }
        let sealed = try Self.seal(sendKey, sendCounter, Data(), plaintext)
        sendCounter += 1
        return sealed
    }

    func decrypt(_ ciphertext: Data) throws -> Data {
        guard let receiveKey else { throw LinkError("NOISE_NOT_READY", "The secure handshake is not complete.") }
        let opened = try Self.open(receiveKey, receiveCounter, Data(), ciphertext)
        receiveCounter += 1
        return opened
    }

    private func mixHash(_ data: Data) {
        h = Data(SHA256.hash(data: h + data))
    }

    private func mixKey(_ material: Data) {
        let (chain, key) = Self.hkdf(ck, material)
        ck = chain
        k = SymmetricKey(data: key)
        n = 0
    }

    private func encryptAndHash(_ plaintext: Data) throws -> Data {
        guard let k else { mixHash(plaintext); return plaintext }
        let sealed = try Self.seal(k, n, h, plaintext)
        n += 1
        mixHash(sealed)
        return sealed
    }

    private func decryptAndHash(_ ciphertext: Data) throws -> Data {
        guard let k else { mixHash(ciphertext); return ciphertext }
        let opened = try Self.open(k, n, h, ciphertext)
        n += 1
        mixHash(ciphertext)
        return opened
    }

    private static func dh(_ key: PrivateKey, _ peer: PublicKey) throws -> Data {
        try key.sharedSecretFromKeyAgreement(with: peer).withUnsafeBytes { Data($0) }
    }

    private static func hmac(_ key: Data, _ data: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: key)))
    }

    private static func hkdf(_ chainingKey: Data, _ material: Data) -> (Data, Data) {
        let temp = hmac(chainingKey, material)
        let first = hmac(temp, Data([1]))
        let second = hmac(temp, first + Data([2]))
        return (first, second)
    }

    private static func nonce(_ counter: UInt64) throws -> ChaChaPoly.Nonce {
        var bytes = Data(repeating: 0, count: 4)
        withUnsafeBytes(of: counter.littleEndian) { bytes.append(contentsOf: $0) }
        return try ChaChaPoly.Nonce(data: bytes)
    }

    private static func seal(_ key: SymmetricKey, _ counter: UInt64, _ associated: Data, _ plaintext: Data) throws -> Data {
        let box = try ChaChaPoly.seal(plaintext, using: key, nonce: nonce(counter), authenticating: associated)
        return box.ciphertext + box.tag
    }

    private static func open(_ key: SymmetricKey, _ counter: UInt64, _ associated: Data, _ ciphertext: Data) throws -> Data {
        guard ciphertext.count >= 16 else { throw LinkError("DECRYPT_FAILED", "The message is too short.") }
        let box = try ChaChaPoly.SealedBox(
            nonce: nonce(counter),
            ciphertext: Data(ciphertext.dropLast(16)),
            tag: Data(ciphertext.suffix(16))
        )
        return try ChaChaPoly.open(box, using: key, authenticating: associated)
    }
}
