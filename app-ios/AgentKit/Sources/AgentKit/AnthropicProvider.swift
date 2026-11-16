import Foundation

/// Claude's Messages API.
public struct AnthropicProvider: ModelProvider {
    public var baseURL: String
    public var apiKey: String

    public init(baseURL: String = "https://api.anthropic.com", apiKey: String) {
        self.baseURL = baseURL
        self.apiKey = apiKey
    }

    private func signed(_ url: URL) -> URLRequest {
        var http = URLRequest(url: url)
        http.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        http.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        http.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return http
    }

    public func stream(_ request: ModelRequest) -> AsyncThrowingStream<StreamEvent, Error> {
        do {
            var http = signed(try HTTP.endpoint(baseURL, "/v1/messages"))
            http.httpMethod = "POST"
            http.httpBody = try HTTP.json(Self.body(request))
            return HTTP.stream(http, decode: Self.decode)
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }
    }

    public func models() async throws -> [String] {
        let list = try await HTTP.get(signed(try HTTP.endpoint(baseURL, "/v1/models?limit=100")))
        return (list["data"]?.array ?? []).compactMap { $0["id"]?.string }
    }

    static func body(_ request: ModelRequest) -> [String: Any] {
        // Claude wants turns to alternate, and tool results inside a user turn.
        var turns: [(role: String, blocks: [[String: Any]])] = []
        func add(_ role: String, _ blocks: [[String: Any]]) {
            guard !blocks.isEmpty else { return }
            if let last = turns.last, last.role == role {
                turns[turns.count - 1].blocks.append(contentsOf: blocks)
            } else {
                turns.append((role, blocks))
            }
        }
        for message in request.messages {
            switch message.role {
            case .user:
                var blocks: [[String: Any]] = message.images.map { image in
                    ["type": "image", "source": ["type": "base64", "media_type": image.mediaType, "data": image.data.base64EncodedString()]]
                }
                if !message.text.isEmpty { blocks.append(["type": "text", "text": message.text]) }
                add("user", blocks)
            case .assistant:
                var blocks: [[String: Any]] = []
                if !message.text.isEmpty { blocks.append(["type": "text", "text": message.text]) }
                for call in message.toolCalls {
                    var input: Any = [String: Any]()
                    if let parsed = JSONValue.parse(call.arguments), case .object = parsed { input = parsed.any }
                    blocks.append(["type": "tool_use", "id": call.id, "name": call.name, "input": input])
                }
                add("assistant", blocks)
            case .tool:
                var block: [String: Any] = ["type": "tool_result", "tool_use_id": message.toolCallId ?? "", "content": message.text.isEmpty ? "（空）" : message.text]
                if message.isError { block["is_error"] = true }
                add("user", [block])
            }
        }
        var body: [String: Any] = [
            "model": request.model,
            "max_tokens": request.maxTokens,
            "stream": true,
            "messages": turns.map { ["role": $0.role, "content": $0.blocks] },
        ]
        if !request.system.isEmpty { body["system"] = request.system }
        if !request.tools.isEmpty {
            body["tools"] = request.tools.map { ["name": $0.name, "description": $0.description, "input_schema": $0.parameters.any] }
        }
        return body
    }

    static func decode(_ payload: String) throws -> [StreamEvent] {
        guard let json = JSONValue.parse(payload), let type = json["type"]?.string else { return [] }
        switch type {
        case "message_start":
            let usage = json["message"]?["usage"]
            if let input = usage?["input_tokens"]?.number { return [.usage(input: Int(input), output: 0)] }
        case "content_block_start":
            let index = Int(json["index"]?.number ?? 0)
            let block = json["content_block"] ?? .null
            switch block["type"]?.string {
            case "tool_use":
                return [.toolCallStart(index: index, id: block["id"]?.string ?? "", name: block["name"]?.string ?? "")]
            case "text":
                if let text = block["text"]?.string, !text.isEmpty { return [.text(text)] }
            default: break
            }
        case "content_block_delta":
            let index = Int(json["index"]?.number ?? 0)
            let delta = json["delta"] ?? .null
            switch delta["type"]?.string {
            case "text_delta": if let text = delta["text"]?.string { return [.text(text)] }
            case "input_json_delta": if let part = delta["partial_json"]?.string, !part.isEmpty { return [.toolCallArguments(index: index, delta: part)] }
            case "thinking_delta": if let thought = delta["thinking"]?.string { return [.reasoning(thought)] }
            default: break
            }
        case "message_delta":
            var events: [StreamEvent] = []
            if let output = json["usage"]?["output_tokens"]?.number { events.append(.usage(input: 0, output: Int(output))) }
            if let reason = json["delta"]?["stop_reason"]?.string { events.append(.finish(reason: reason)) }
            return events
        case "error":
            throw ProviderError(json["error"]?["message"]?.string ?? "Claude 报错了")
        default:
            break
        }
        return []
    }
}
