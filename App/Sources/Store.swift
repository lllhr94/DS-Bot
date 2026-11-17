import Foundation
import Security

/// Where the phone keeps its keys and its paired computer: the Keychain,
/// or a protected file when the Keychain refuses (some re-signed installs).
enum Vault {
    private static let service = "io.github.lllhr94.dsbot.link"

    static func save<Value: Encodable>(_ value: Value, as key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        if SecItemAdd(item as CFDictionary, nil) == errSecSuccess {
            try? FileManager.default.removeItem(at: file(key))
        } else {
            try? data.write(to: file(key), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    static func load<Value: Decodable>(_ type: Value.Type, key: String) -> Value? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var found: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &found) == errSecSuccess,
           let data = found as? Data,
           let value = try? JSONDecoder().decode(type, from: data) {
            return value
        }
        guard let data = try? Data(contentsOf: file(key)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func remove(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
        try? FileManager.default.removeItem(at: file(key))
    }

    private static func file(_ key: String) -> URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("link-\(key).json")
    }
}
