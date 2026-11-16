import Foundation

/// A tool as a model sees it.
public struct ToolSpec: Equatable, Sendable {
    public var name: String
    public var description: String
    /// JSON Schema of the arguments.
    public var parameters: JSONValue

    public init(name: String, description: String, parameters: JSONValue) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }
}

public struct ModelRequest: Sendable {
    public var model: String
    public var system: String
    public var messages: [Message]
    public var tools: [ToolSpec]
    public var maxTokens: Int

    public init(model: String, system: String, messages: [Message], tools: [ToolSpec] = [], maxTokens: Int = 8192) {
        self.model = model
        self.system = system
        self.messages = messages
        self.tools = tools
        self.maxTokens = maxTokens
    }
}

/// What a model's stream says, one piece at a time.
public enum StreamEvent: Equatable, Sendable {
    case text(String)
    case reasoning(String)
    /// A tool call begins; `index` keeps its pieces together.
    case toolCallStart(index: Int, id: String, name: String)
    case toolCallArguments(index: Int, delta: String)
    case finish(reason: String?)
    case usage(input: Int, output: Int)
}

public struct ProviderError: Error, LocalizedError, Equatable {
    public var status: Int?
    public var message: String

    public init(status: Int? = nil, _ message: String) {
        self.status = status
        self.message = message
    }

    public var errorDescription: String? {
        guard let code = status else { return message }
        switch code {
        case 401, 403: return "密钥不对或没有权限（\(code)）：\(message)"
        case 402: return "账户余额不足：\(message)"
        case 429: return "请求太频繁或额度用完了：\(message)"
        case 500...: return "模型服务暂时出错（\(code)）：\(message)"
        default: return "模型服务拒绝了请求（\(code)）：\(message)"
        }
    }
}

public protocol ModelProvider: Sendable {
    func stream(_ request: ModelRequest) -> AsyncThrowingStream<StreamEvent, Error>
    /// The models this key can use.
    func models() async throws -> [String]
}

/// Server-Sent Events: the JSON after `data:` on one line.
enum SSE {
    static func payload(of line: String) -> String? {
        guard line.hasPrefix("data:") else { return nil }
        let rest = line.dropFirst(5)
        let text = rest.first == " " ? String(rest.dropFirst()) : String(rest)
        return text.isEmpty ? nil : text
    }
}

enum HTTP {
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 900
        return URLSession(configuration: configuration)
    }()

    /// Reads an error body and finds the message in it.
    static func failure(status: Int, bytes: URLSession.AsyncBytes) async -> ProviderError {
        var data = Data()
        do {
            for try await byte in bytes {
                data.append(byte)
                if data.count > 8000 { break }
            }
        } catch {}
        return failure(status: status, data: data)
    }

    static func failure(status: Int, data: Data) -> ProviderError {
        let text = String(decoding: data, as: UTF8.self)
        if let json = JSONValue.parse(text) {
            if let message = json["error"]?["message"]?.string ?? json["message"]?.string ?? json["error"]?.string {
                return ProviderError(status: status, message)
            }
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return ProviderError(status: status, trimmed.isEmpty ? "没有说明" : String(trimmed.prefix(300)))
    }

    static func json(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes])
    }

    /// Runs a streaming request and passes each SSE data line to `decode`.
    static func stream(_ request: URLRequest, decode: @escaping @Sendable (String) throws -> [StreamEvent]) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard status == 200 else { throw await failure(status: status, bytes: bytes) }
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard let payload = SSE.payload(of: line), payload != "[DONE]" else { continue }
                        for event in try decode(payload) { continuation.yield(event) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func get(_ request: URLRequest) async throws -> JSONValue {
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw failure(status: status, data: data) }
        guard let value = JSONValue.parse(String(decoding: data, as: UTF8.self)) else { throw ProviderError(status: status, "返回的不是 JSON") }
        return value
    }

    static func endpoint(_ base: String, _ path: String) throws -> URL {
        var trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard let url = URL(string: trimmed + path), url.scheme?.hasPrefix("http") == true else {
            throw ProviderError("服务地址不对：\(base)")
        }
        return url
    }
}
