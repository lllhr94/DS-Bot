import Foundation

/// What a tool needs the user to agree to before it runs.
public struct ApprovalAsk: Equatable, Sendable {
    /// What will happen, in a few words: 「新建日程」.
    public var title: String
    /// Why, or the thing itself: 「明天 15:00 牙医」.
    public var reason: String
    public var detail: String?

    public init(title: String, reason: String, detail: String? = nil) {
        self.title = title
        self.reason = reason
        self.detail = detail
    }
}

public struct ToolOutput: Equatable, Sendable {
    public var text: String
    public var isError: Bool

    public init(_ text: String, isError: Bool = false) {
        self.text = text
        self.isError = isError
    }
}

public protocol AgentTool: Sendable {
    var spec: ToolSpec { get }
    /// What the user sees while it runs: 「搜索：重庆天气」.
    func label(for arguments: JSONValue) -> String
    /// Nil: runs without asking.
    func approval(for arguments: JSONValue) -> ApprovalAsk?
    func run(_ arguments: JSONValue) async throws -> ToolOutput
}

public extension AgentTool {
    func approval(for arguments: JSONValue) -> ApprovalAsk? { nil }
}

public enum AgentEvent: Equatable, Sendable {
    case text(String)
    case reasoning(String)
    case toolStarted(id: String, name: String, label: String)
    case toolFinished(id: String, ok: Bool)
    /// A finished message, to keep.
    case message(Message)
    case usage(input: Int, output: Int)
}

/// One Bot's turn: asks the model, runs the tools it calls, and asks again until it answers.
public struct Agent: Sendable {
    public var provider: ModelProvider
    public var model: String
    public var system: String
    public var tools: [AgentTool]
    public var maxSteps: Int
    public var approve: @Sendable (ApprovalAsk, String) async -> Bool

    public init(provider: ModelProvider, model: String, system: String, tools: [AgentTool] = [], maxSteps: Int = 16, approve: @escaping @Sendable (ApprovalAsk, String) async -> Bool = { _, _ in false }) {
        self.provider = provider
        self.model = model
        self.system = system
        self.tools = tools
        self.maxSteps = maxSteps
        self.approve = approve
    }

    public func run(history: [Message], emit: @escaping @Sendable (AgentEvent) async -> Void) async throws {
        var messages = history
        let specs = tools.map(\.spec)
        for _ in 0..<maxSteps {
            try Task.checkCancellation()
            let request = ModelRequest(model: model, system: system, messages: messages, tools: specs)
            var text = ""
            var reasoning = ""
            var calls: [Int: ToolCall] = [:]
            var order: [Int] = []
            do {
                for try await event in provider.stream(request) {
                    switch event {
                    case .text(let piece):
                        text += piece
                        await emit(.text(piece))
                    case .reasoning(let piece):
                        reasoning += piece
                        await emit(.reasoning(piece))
                    case .toolCallStart(let index, let id, let name):
                        if calls[index] == nil { order.append(index) }
                        calls[index] = ToolCall(id: id, name: name, arguments: calls[index]?.arguments ?? "")
                    case .toolCallArguments(let index, let delta):
                        if calls[index] == nil {
                            order.append(index)
                            calls[index] = ToolCall(id: "call_\(index)", name: "", arguments: "")
                        }
                        calls[index]?.arguments += delta
                    case .usage(let input, let output):
                        await emit(.usage(input: input, output: output))
                    case .finish:
                        break
                    }
                }
            } catch {
                // What was written so far stays.
                if !text.isEmpty { await emit(.message(.assistant(text))) }
                if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                    throw CancellationError()
                }
                throw error
            }
            let made = order.compactMap { calls[$0] }.filter { !$0.name.isEmpty }
            let reply = Message.assistant(text, toolCalls: made, reasoning: reasoning.isEmpty ? nil : reasoning)
            if !text.isEmpty || !made.isEmpty {
                messages.append(reply)
                await emit(.message(reply))
            }
            if made.isEmpty {
                if Task.isCancelled { throw CancellationError() }
                return
            }
            for call in made {
                let result = await perform(call, emit: emit)
                messages.append(result)
                await emit(.message(result))
                try Task.checkCancellation()
            }
        }
        await emit(.message(.assistant("（这件事步骤太多，我先停在这里。要我接着做就说一声。）")))
    }

    private func perform(_ call: ToolCall, emit: @Sendable (AgentEvent) async -> Void) async -> Message {
        guard let tool = tools.first(where: { $0.spec.name == call.name }) else {
            return .toolResult("没有叫 \(call.name) 的工具。", for: call, isError: true)
        }
        let source = call.arguments.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let arguments = JSONValue.parse(source.isEmpty ? "{}" : source) else {
            return .toolResult("参数不是合法的 JSON：\(call.arguments.prefix(200))", for: call, isError: true)
        }
        await emit(.toolStarted(id: call.id, name: call.name, label: tool.label(for: arguments)))
        if let ask = tool.approval(for: arguments) {
            guard await approve(ask, call.name) else {
                await emit(.toolFinished(id: call.id, ok: false))
                return .toolResult("用户没有同意这次操作，什么都没做。除非用户再次要求，不要重试。", for: call, isError: true)
            }
        }
        do {
            let output = try await tool.run(arguments)
            await emit(.toolFinished(id: call.id, ok: !output.isError))
            return .toolResult(output.text, for: call, isError: output.isError)
        } catch {
            await emit(.toolFinished(id: call.id, ok: false))
            return .toolResult("出错了：\(error.localizedDescription)", for: call, isError: true)
        }
    }
}
