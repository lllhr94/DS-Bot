import CryptoKit
import Foundation

public struct LinkError: Error, Sendable, Equatable, CustomStringConvertible {
    public let code: String
    public let message: String

    public init(_ code: String, _ message: String) {
        self.code = code
        self.message = message
    }

    public var description: String { "\(code): \(message)" }
}

enum Base64URL {
    static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ text: String) -> Data? {
        var padded = text
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while padded.count % 4 != 0 { padded.append("=") }
        return Data(base64Encoded: padded)
    }
}

public enum LinkKeys {
    /// A device's id is derived from its identity key, so the Server can check one against the other.
    public static func deviceId(forPublicKey key: String) throws -> String {
        guard let raw = Base64URL.decode(key), raw.count == 32 else {
            throw LinkError("INVALID_KEY", "X25519 public keys must be 32 bytes.")
        }
        return "d-" + Base64URL.encode(Data(Data(SHA256.hash(data: raw)).prefix(16)))
    }

    /// Short code both screens show at pairing, so the user can see they hold the same key.
    public static func fingerprint(ofPublicKey key: String) -> String {
        guard let raw = Base64URL.decode(key) else { return "" }
        return Data(SHA256.hash(data: raw)).prefix(6).map { String(format: "%02X", $0) }.joined()
    }

    static func randomToken(bytes: Int = 32) -> String {
        var generator = SystemRandomNumberGenerator()
        return Base64URL.encode(Data((0..<bytes).map { _ in UInt8.random(in: .min ... .max, using: &generator) }))
    }
}

/// This phone's own keys. Keep it in the Keychain: the private key never leaves the phone.
public struct LinkIdentity: Codable, Sendable, Equatable {
    public let deviceId: String
    public let publicKey: String
    public let privateKey: String
    public let accessToken: String

    public static func generate() -> LinkIdentity {
        let key = Curve25519.KeyAgreement.PrivateKey()
        let publicKey = Base64URL.encode(key.publicKey.rawRepresentation)
        return LinkIdentity(
            deviceId: "d-" + Base64URL.encode(Data(Data(SHA256.hash(data: key.publicKey.rawRepresentation)).prefix(16))),
            publicKey: publicKey,
            privateKey: Base64URL.encode(key.rawRepresentation),
            accessToken: LinkKeys.randomToken()
        )
    }
}

/// The computer this phone is paired with.
public struct PairedHost: Codable, Sendable, Equatable {
    public let deviceId: String
    public let identityKey: String
    public let server: String
    public var name: String

    public init(deviceId: String, identityKey: String, server: String, name: String) {
        self.deviceId = deviceId
        self.identityKey = identityKey
        self.server = server
        self.name = name
    }
}

/// What the computer's pairing QR code carries.
public struct PairingOffer: Sendable, Equatable {
    public let server: String
    public let hostDeviceId: String
    public let hostKey: String
    public let code: String
    public let name: String

    public var host: PairedHost { PairedHost(deviceId: hostDeviceId, identityKey: hostKey, server: server, name: name) }

    public static func parse(_ uri: String) throws -> PairingOffer {
        let invalid = LinkError("INVALID_PAIRING_CODE", "This is not a DS Bot pairing code.")
        guard var parts = URLComponents(string: uri.trimmingCharacters(in: .whitespacesAndNewlines)),
              parts.scheme == "dsbot", parts.host == "pair" else { throw invalid }
        // The computer writes spaces as "+", which URLComponents leaves alone.
        parts.percentEncodedQuery = parts.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%20")
        var fields: [String: String] = [:]
        for item in parts.queryItems ?? [] { fields[item.name] = item.value ?? "" }
        guard fields["v"] == "1" else { throw invalid }
        func field(_ name: String) throws -> String {
            guard let value = fields[name], !value.isEmpty else {
                throw LinkError("INVALID_PAIRING_CODE", "The pairing code has no \(name).")
            }
            return value
        }
        let server = try field("server")
        guard let scheme = URL(string: server)?.scheme, scheme == "ws" || scheme == "wss" else {
            throw LinkError("INVALID_PAIRING_CODE", "The pairing code names an invalid Server.")
        }
        let offer = PairingOffer(
            server: server,
            hostDeviceId: try field("host"),
            hostKey: try field("key"),
            code: try field("code"),
            name: String((fields["name"] ?? "").prefix(64))
        )
        guard try LinkKeys.deviceId(forPublicKey: offer.hostKey) == offer.hostDeviceId else {
            throw LinkError("INVALID_PAIRING_CODE", "The pairing code does not match its computer.")
        }
        return offer
    }
}
