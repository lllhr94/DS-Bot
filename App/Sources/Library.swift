import AgentKit
import Foundation

/// A Bot as this phone keeps it.
struct BotInfo: Codable, Identifiable, Equatable {
    struct Blocked: Codable, Equatable { var code: String? }

    let id: String
    var name: String
    var role: String?
    var color: String?
    var main: Bool?
    /// Who it is and how it talks, in the user's words.
    var instructions: String?
    /// `endpointId/modelId`; nil: the default model.
    var model: String?
    var preview: String?
    /// Milliseconds.
    var lastAt: Double?
    var blocked: Blocked?
    var createdAt: Double?
}

struct RoomInfo: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var preview: String?
    var members: [String]?
    var lastAt: Double?
}

/// One message of a chat, as kept on the phone. Photos live in their own files.
struct Entry: Codable, Identifiable, Equatable {
    var id: String
    /// Milliseconds.
    var at: Double
    var message: Message
    /// In a group: the Bot that said it.
    var speaker: String?
    /// File names under `media/`.
    var photos: [String] = []
    /// What the user saw while the tool ran: 「搜索：重庆天气」.
    var label: String?
    /// Not for the model: a line for the user only.
    var note: Bool?
}

/// Something the user told a Bot to remember about them.
struct Memory: Codable, Identifiable, Equatable {
    var id: String
    var text: String
    var at: Double
    var by: String?
}

/// A message a Bot set for later; it shows in the chat once its time has come.
struct Later: Codable, Identifiable, Equatable {
    var id: String
    var chat: String
    var botId: String
    var text: String
    /// Seconds since 1970.
    var at: Double
}

/// A model service the user added: its address and which models it has. The key is in the Vault.
struct Endpoint: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case openai, anthropic }

    var id: String
    var name: String
    var kind: Kind
    var baseURL: String
    var models: [String]
    /// False when its models cannot look at photos.
    var vision: Bool?

    static let presets: [Endpoint] = [
        Endpoint(id: "deepseek", name: "DeepSeek", kind: .openai, baseURL: "https://api.deepseek.com", models: ["deepseek-chat", "deepseek-reasoner"], vision: false),
        Endpoint(id: "claude", name: "Claude", kind: .anthropic, baseURL: "https://api.anthropic.com", models: [], vision: true),
        Endpoint(id: "custom", name: "其他（OpenAI 兼容）", kind: .openai, baseURL: "https://", models: [], vision: true),
    ]

    func provider(key: String) -> ModelProvider {
        switch kind {
        case .openai: return OpenAIProvider(baseURL: baseURL, apiKey: key)
        case .anthropic: return AnthropicProvider(baseURL: baseURL, apiKey: key)
        }
    }
}

struct TeamSettings: Codable, Equatable {
    var endpoints: [Endpoint] = []
    /// `endpointId/modelId`.
    var defaultModel: String?
    var mainBotId: String?
}

/// Everything the app keeps, as small JSON files in Application Support.
enum Disk {
    static let root: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Team", isDirectory: true)
        for folder in ["", "chats", "media"] {
            try? FileManager.default.createDirectory(at: base.appendingPathComponent(folder, isDirectory: true), withIntermediateDirectories: true)
        }
        return base
    }()

    static func url(_ name: String) -> URL { root.appendingPathComponent(name) }

    static func load<Value: Decodable>(_ type: Value.Type, _ name: String) -> Value? {
        guard let data = try? Data(contentsOf: url(name)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func save<Value: Encodable>(_ value: Value, _ name: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url(name), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func remove(_ name: String) {
        try? FileManager.default.removeItem(at: url(name))
    }

    static func chatFile(_ key: String) -> String {
        "chats/\(key.replacingOccurrences(of: "/", with: "_")).json"
    }

    /// Keeps a photo and returns its file name.
    static func keepPhoto(_ data: Data) -> String {
        let name = UUID().uuidString + ".jpg"
        try? data.write(to: url("media/\(name)"), options: .atomic)
        return name
    }

    static func photo(_ name: String) -> Data? {
        try? Data(contentsOf: url("media/\(name)"))
    }
}

enum Now {
    static var ms: Double { Date().timeIntervalSince1970 * 1000 }
}
