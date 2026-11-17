import XCTest
@testable import AgentKit

final class ProviderTests: XCTestCase {
    func testSSEPayload() {
        XCTAssertEqual(SSE.payload(of: "data: {\"a\":1}"), "{\"a\":1}")
        XCTAssertEqual(SSE.payload(of: "data:{\"a\":1}"), "{\"a\":1}")
        XCTAssertNil(SSE.payload(of: "event: ping"))
        XCTAssertNil(SSE.payload(of: ": keep-alive"))
    }

    func testOpenAIDecodesTextReasoningAndUsage() throws {
        XCTAssertEqual(try OpenAIProvider.decode(#"{"choices":[{"index":0,"delta":{"content":"你好"},"finish_reason":null}]}"#), [.text("你好")])
        XCTAssertEqual(try OpenAIProvider.decode(#"{"choices":[{"delta":{"reasoning_content":"想一想","content":null}}]}"#), [.reasoning("想一想")])
        XCTAssertEqual(try OpenAIProvider.decode(#"{"choices":[{"delta":{},"finish_reason":"stop"}],"usage":{"prompt_tokens":12,"completion_tokens":3}}"#), [.finish(reason: "stop"), .usage(input: 12, output: 3)])
        XCTAssertEqual(try OpenAIProvider.decode(#"{"choices":[],"usage":null}"#), [])
    }

    func testOpenAIDecodesToolCalls() throws {
        XCTAssertEqual(
            try OpenAIProvider.decode(#"{"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"web_search","arguments":""}}]}}]}"#),
            [.toolCallStart(index: 0, id: "call_1", name: "web_search")]
        )
        XCTAssertEqual(
            try OpenAIProvider.decode(#"{"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\"query\":"}}]}}]}"#),
            [.toolCallArguments(index: 0, delta: "{\"query\":")]
        )
    }

    func testOpenAIErrorInStream() {
        XCTAssertThrowsError(try OpenAIProvider.decode(#"{"error":{"message":"bad"}}"#))
    }

    func testOpenAIBody() throws {
        let call = ToolCall(id: "c1", name: "web_search", arguments: "{\"query\":\"x\"}")
        let request = ModelRequest(
            model: "deepseek-chat",
            system: "你是助手",
            messages: [
                .user("早"),
                .assistant("早上好", reasoning: "旧的想法"),
                .user("搜一下", images: [ImagePart(data: Data([1, 2, 3]))]),
                .assistant("", toolCalls: [call], reasoning: "要搜"),
                .toolResult("结果", for: call),
            ],
            tools: [WebSearchTool().spec]
        )
        let body = OpenAIProvider.body(request)
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 6)
        XCTAssertEqual(messages[0]["role"] as? String, "system")
        // Thoughts from earlier turns are dropped; the running turn keeps them.
        XCTAssertNil(messages[2]["reasoning_content"])
        XCTAssertEqual(messages[4]["reasoning_content"] as? String, "要搜")
        let parts = try XCTUnwrap(messages[3]["content"] as? [[String: Any]])
        XCTAssertEqual(parts.first?["type"] as? String, "image_url")
        XCTAssertEqual(((parts.first?["image_url"] as? [String: Any])?["url"] as? String), "data:image/jpeg;base64,AQID")
        let calls = try XCTUnwrap(messages[4]["tool_calls"] as? [[String: Any]])
        XCTAssertEqual((calls[0]["function"] as? [String: Any])?["name"] as? String, "web_search")
        XCTAssertEqual(messages[5]["role"] as? String, "tool")
        XCTAssertEqual(messages[5]["tool_call_id"] as? String, "c1")
        let tools = try XCTUnwrap(body["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.count, 1)
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: body))
    }

    func testAnthropicDecode() throws {
        XCTAssertEqual(try AnthropicProvider.decode(#"{"type":"message_start","message":{"usage":{"input_tokens":20,"output_tokens":1}}}"#), [.usage(input: 20, output: 0)])
        XCTAssertEqual(try AnthropicProvider.decode(#"{"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_1","name":"web_read","input":{}}}"#), [.toolCallStart(index: 1, id: "toolu_1", name: "web_read")])
        XCTAssertEqual(try AnthropicProvider.decode(#"{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"url\""}}"#), [.toolCallArguments(index: 1, delta: "{\"url\"")])
        XCTAssertEqual(try AnthropicProvider.decode(#"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"嗨"}}"#), [.text("嗨")])
        XCTAssertEqual(try AnthropicProvider.decode(#"{"type":"message_delta","delta":{"stop_reason":"tool_use"},"usage":{"output_tokens":9}}"#), [.usage(input: 0, output: 9), .finish(reason: "tool_use")])
        XCTAssertEqual(try AnthropicProvider.decode(#"{"type":"ping"}"#), [])
        XCTAssertThrowsError(try AnthropicProvider.decode(#"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#))
    }

    func testAnthropicBodyMergesToolResultsIntoUserTurns() throws {
        let first = ToolCall(id: "t1", name: "a", arguments: "{\"x\":1}")
        let second = ToolCall(id: "t2", name: "b", arguments: "")
        let request = ModelRequest(model: "claude", system: "sys", messages: [
            .user("hi"),
            .assistant("ok", toolCalls: [first, second]),
            .toolResult("one", for: first),
            .toolResult("", for: second, isError: true),
            .user("再来"),
        ])
        let body = AnthropicProvider.body(request)
        XCTAssertEqual(body["system"] as? String, "sys")
        let turns = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(turns.map { $0["role"] as? String }, ["user", "assistant", "user"])
        let assistant = try XCTUnwrap(turns[1]["content"] as? [[String: Any]])
        XCTAssertEqual(assistant.map { $0["type"] as? String }, ["text", "tool_use", "tool_use"])
        XCTAssertEqual((assistant[1]["input"] as? [String: Any])?["x"] as? Int, 1)
        XCTAssertNotNil(assistant[2]["input"] as? [String: Any])
        let results = try XCTUnwrap(turns[2]["content"] as? [[String: Any]])
        XCTAssertEqual(results.map { $0["type"] as? String }, ["tool_result", "tool_result", "text"])
        XCTAssertEqual(results[1]["is_error"] as? Bool, true)
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: body))
    }

    func testProviderErrorMessage() {
        let error = HTTP.failure(status: 401, data: Data(#"{"error":{"message":"Authentication Fails"}}"#.utf8))
        XCTAssertEqual(error, ProviderError(status: 401, "Authentication Fails"))
        XCTAssertTrue(error.localizedDescription.contains("密钥"))
    }

    func testEndpointJoin() throws {
        XCTAssertEqual(try HTTP.endpoint("https://api.deepseek.com/", "/chat/completions").absoluteString, "https://api.deepseek.com/chat/completions")
        XCTAssertThrowsError(try HTTP.endpoint("api.deepseek.com", "/models"))
    }
}

/// A model that answers from a script, one reply per request.
private final class ScriptedProvider: ModelProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var replies: [[StreamEvent]]
    private(set) var requests: [ModelRequest] = []

    init(_ replies: [[StreamEvent]]) { self.replies = replies }

    func stream(_ request: ModelRequest) -> AsyncThrowingStream<StreamEvent, Error> {
        lock.lock()
        requests.append(request)
        let reply = replies.isEmpty ? [StreamEvent.text("（没了）")] : replies.removeFirst()
        lock.unlock()
        return AsyncThrowingStream { continuation in
            for event in reply { continuation.yield(event) }
            continuation.finish()
        }
    }

    func models() async throws -> [String] { ["scripted"] }
}

private struct EchoTool: AgentTool {
    var asks = false
    var spec: ToolSpec { ToolSpec(name: "echo", description: "", parameters: ["type": "object"]) }
    func label(for arguments: JSONValue) -> String { "回声：\(arguments["say"]?.string ?? "")" }
    func approval(for arguments: JSONValue) -> ApprovalAsk? { asks ? ApprovalAsk(title: "回声", reason: "要说话") : nil }
    func run(_ arguments: JSONValue) async throws -> ToolOutput { ToolOutput("你说了 \(arguments["say"]?.string ?? "")") }
}

private actor Recorder {
    var events: [AgentEvent] = []
    func add(_ event: AgentEvent) { events.append(event) }
}

final class AgentTests: XCTestCase {
    func testRunsToolThenAnswers() async throws {
        let provider = ScriptedProvider([
            [.text("我查一下"), .toolCallStart(index: 0, id: "c1", name: "echo"), .toolCallArguments(index: 0, delta: "{\"say\":"), .toolCallArguments(index: 0, delta: "\"嗨\"}"), .finish(reason: "tool_calls")],
            [.text("好了"), .finish(reason: "stop")],
        ])
        let recorder = Recorder()
        let agent = Agent(provider: provider, model: "m", system: "s", tools: [EchoTool()])
        try await agent.run(history: [.user("说嗨")]) { await recorder.add($0) }
        let events = await recorder.events
        let messages = events.compactMap { event -> Message? in if case .message(let message) = event { return message } else { return nil } }
        XCTAssertEqual(messages.map(\.role), [.assistant, .tool, .assistant])
        XCTAssertEqual(messages[0].toolCalls, [ToolCall(id: "c1", name: "echo", arguments: "{\"say\":\"嗨\"}")])
        XCTAssertEqual(messages[1].text, "你说了 嗨")
        XCTAssertEqual(messages[2].text, "好了")
        XCTAssertTrue(events.contains(.toolStarted(id: "c1", name: "echo", label: "回声：嗨")))
        XCTAssertTrue(events.contains(.toolFinished(id: "c1", ok: true)))
        XCTAssertEqual(provider.requests.count, 2)
        XCTAssertEqual(provider.requests[1].messages.count, 3)
    }

    func testDeclinedApprovalDoesNotRun() async throws {
        let provider = ScriptedProvider([
            [.toolCallStart(index: 0, id: "c1", name: "echo"), .toolCallArguments(index: 0, delta: "{}")],
            [.text("好的，不做了")],
        ])
        let recorder = Recorder()
        let agent = Agent(provider: provider, model: "m", system: "", tools: [EchoTool(asks: true)]) { _, _ in false }
        try await agent.run(history: [.user("说")]) { await recorder.add($0) }
        let results = await recorder.events.compactMap { event -> Message? in
            if case .message(let message) = event, message.role == .tool { return message } else { return nil }
        }
        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results[0].isError)
        XCTAssertTrue(results[0].text.contains("没有同意"))
    }

    func testBadArgumentsAndUnknownTool() async throws {
        let provider = ScriptedProvider([
            [.toolCallStart(index: 0, id: "a", name: "echo"), .toolCallArguments(index: 0, delta: "{not json"),
             .toolCallStart(index: 1, id: "b", name: "nope"), .toolCallArguments(index: 1, delta: "{}")],
            [.text("抱歉")],
        ])
        let recorder = Recorder()
        try await Agent(provider: provider, model: "m", system: "", tools: [EchoTool()]).run(history: [.user("x")]) { await recorder.add($0) }
        let results = await recorder.events.compactMap { event -> Message? in
            if case .message(let message) = event, message.role == .tool { return message } else { return nil }
        }
        XCTAssertEqual(results.map(\.isError), [true, true])
    }
}

final class WebTextTests: XCTestCase {
    func testPageText() {
        let html = """
        <html><head><title>天气 &amp; 预报</title><style>p{}</style></head>
        <body><nav>菜单</nav><h1>重庆</h1><p>今天 <b>晴</b>，18&#8451;。</p><script>var x=1</script>
        <ul><li>早上 12 度</li><li>下午 20 度</li></ul><footer>版权</footer></body></html>
        """
        let page = WebText.page(html)
        XCTAssertEqual(page.title, "天气 & 预报")
        XCTAssertEqual(page.text, "重庆\n\n今天 晴，18℃。\n\n• 早上 12 度\n• 下午 20 度")
    }

    func testBingResults() {
        let html = """
        <ol id="b_results"><li class="b_algo" data-x="1"><h2><a href="https://www.bing.com/ck/a?!&amp;&amp;p=abc&amp;u=a1aHR0cHM6Ly9leGFtcGxlLmNvbS9hP2I9MQ&amp;ntb=1" h="ID=1">示例 <strong>标题</strong></a></h2>
        <div class="b_caption"><p class="b_lineclamp2">这是&nbsp;摘要</p></div></li>
        <li class="b_algo"><h2><a href="https://direct.example.org/x">直接链接</a></h2><p>第二条</p></li></ol>
        """
        let results = WebText.bingResults(html)
        XCTAssertEqual(results, [
            WebText.Result(title: "示例 标题", url: "https://example.com/a?b=1", snippet: "这是 摘要"),
            WebText.Result(title: "直接链接", url: "https://direct.example.org/x", snippet: "第二条"),
        ])
    }

    func testDuckResults() {
        let html = """
        <div class="result__body"><a rel="nofollow" class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fexample.com%2Fp&amp;rut=1">鸭子</a>
        <a class="result__snippet" href="x">一段 <b>摘要</b></a></div>
        """
        XCTAssertEqual(WebText.duckResults(html), [WebText.Result(title: "鸭子", url: "https://example.com/p", snippet: "一段 摘要")])
    }

    func testDecodesGBK() {
        let gbk = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        let data = "<meta charset=\"gbk\"><p>你好</p>".data(using: gbk)!
        XCTAssertTrue(WebText.decode(data, encodingName: nil).contains("你好"))
        XCTAssertTrue(WebText.decode(data, encodingName: "GBK").contains("你好"))
    }

    func testJSONValue() {
        let value = JSONValue.parse(#"{"a":[1,true,"x",null],"b":{"c":2.5}}"#)
        XCTAssertEqual(value?["a"]?.array?.count, 4)
        XCTAssertEqual(value?["a"]?.array?[1], .bool(true))
        XCTAssertEqual(value?["b"]?["c"]?.number, 2.5)
        XCTAssertEqual(JSONValue.parse(value!.compact), value)
    }
}
