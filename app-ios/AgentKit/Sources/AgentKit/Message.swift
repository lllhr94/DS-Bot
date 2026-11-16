import Foundation

public struct ImagePart: Codable, Equatable, Sendable {
    public var mediaType: String
    public var data: Data

    public init(mediaType: String = "image/jpeg", data: Data) {
        self.mediaType = mediaType
        self.data = data
    }
}

public struct ToolCall: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    /// The arguments as the model wrote them: JSON text.
    public var arguments: String

    public init(id: String, name: String, arguments: String) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}

/// One message of a conversation, in a shape every provider can be written from.
public struct Message: Codable, Equatable, Sendable {
    public enum Role: String, Codable, Sendable { case user, assistant, tool }

    public var role: Role
    public var text: String
    public var images: [ImagePart]
    /// What a thinking model thought before it answered.
    public var reasoning: String?
    /// An assistant message's tool calls.
    public var toolCalls: [ToolCall]
    /// A tool message: the call it answers.
    public var toolCallId: String?
    public var toolName: String?
    public var isError: Bool

    public init(role: Role, text: String, images: [ImagePart] = [], reasoning: String? = nil, toolCalls: [ToolCall] = [], toolCallId: String? = nil, toolName: String? = nil, isError: Bool = false) {
        self.role = role
        self.text = text
        self.images = images
        self.reasoning = reasoning
        self.toolCalls = toolCalls
        self.toolCallId = toolCallId
        self.toolName = toolName
        self.isError = isError
    }

    public static func user(_ text: String, images: [ImagePart] = []) -> Message {
        Message(role: .user, text: text, images: images)
    }

    public static func assistant(_ text: String, toolCalls: [ToolCall] = [], reasoning: String? = nil) -> Message {
        Message(role: .assistant, text: text, reasoning: reasoning, toolCalls: toolCalls)
    }

    public static func toolResult(_ text: String, for call: ToolCall, isError: Bool = false) -> Message {
        Message(role: .tool, text: text, toolCallId: call.id, toolName: call.name, isError: isError)
    }
}
