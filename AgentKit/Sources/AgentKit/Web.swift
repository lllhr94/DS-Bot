import Foundation

/// Turns web pages into text a model can read, and search result pages into a list.
public enum WebText {
    public struct Page: Equatable, Sendable {
        public var title: String
        public var text: String
    }

    public struct Result: Equatable, Sendable {
        public var title: String
        public var url: String
        public var snippet: String
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
    }

    private static func replace(_ text: String, _ pattern: String, with template: String) -> String {
        regex(pattern).stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }

    private static func first(_ text: String, _ pattern: String) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex(pattern).firstMatch(in: text, range: range), match.numberOfRanges > 1,
              let found = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[found])
    }

    private static func all(_ text: String, _ pattern: String) -> [[String]] {
        let range = NSRange(text.startIndex..., in: text)
        return regex(pattern).matches(in: text, range: range).map { match in
            (0..<match.numberOfRanges).map { index in
                Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
            }
        }
    }

    /// `&amp;` and friends, and numbered characters.
    public static func entities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var out = text
        for (name, value) in [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&ensp;", " "), ("&emsp;", " "), ("&mdash;", "—"), ("&ndash;", "–"), ("&hellip;", "…"), ("&middot;", "·"), ("&ldquo;", "“"), ("&rdquo;", "”"), ("&lsquo;", "‘"), ("&rsquo;", "’"), ("&copy;", "©")] {
            out = out.replacingOccurrences(of: name, with: value)
        }
        for match in all(out, "&#(x?)([0-9a-f]+);").reversed() {
            let value = match[1].isEmpty ? UInt32(match[2]) : UInt32(match[2], radix: 16)
            if let value, let scalar = Unicode.Scalar(value) {
                out = out.replacingOccurrences(of: match[0], with: String(Character(scalar)))
            }
        }
        return out.replacingOccurrences(of: "&amp;", with: "&")
    }

    /// Tags gone, entities read, spaces tidied: the words of a piece of HTML on one line.
    public static func plain(_ html: String) -> String {
        let bare = entities(replace(html, "<[^>]+>", with: ""))
        return bare.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The readable text of a page, its paragraphs kept apart.
    public static func page(_ html: String) -> Page {
        let title = first(html, "<title[^>]*>(.*?)</title>").map(plain) ?? ""
        var body = first(html, "<body[^>]*>(.*)</body>") ?? html
        for tag in ["script", "style", "noscript", "svg", "template", "nav", "footer", "iframe", "form", "button", "select"] {
            body = replace(body, "<\(tag)\\b[^>]*>.*?</\(tag)>", with: " ")
        }
        body = replace(body, "<!--.*?-->", with: " ")
        body = replace(body, "<li\\b[^>]*>", with: "\n• ")
        body = replace(body, "<(br|hr)\\b[^>]*>", with: "\n")
        body = replace(body, "</?(p|div|section|article|h[1-6]|tr|table|ul|ol|blockquote|pre|header|main|dd|dt|figure|figcaption)\\b[^>]*>", with: "\n")
        body = replace(body, "</t[dh]>", with: " ")
        body = entities(replace(body, "<[^>]+>", with: ""))
        var lines: [String] = []
        for raw in body.components(separatedBy: .newlines) {
            let line = raw.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\u{00A0}" }).joined(separator: " ")
            if line.isEmpty || line == "•" {
                if lines.last?.isEmpty == false { lines.append("") }
            } else {
                lines.append(line)
            }
        }
        return Page(title: title, text: lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Bing's result links point at its own redirect; the real address is in `u`, base64 after `a1`.
    public static func unwrapBing(_ link: String) -> String {
        let link = entities(link)
        guard link.contains("bing.com/ck/a"), let encoded = first(link, "[?&]u=a1([^&]+)") else { return link }
        var base64 = encoded.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64), let url = String(data: data, encoding: .utf8), url.hasPrefix("http") else { return link }
        return url
    }

    public static func bingResults(_ html: String) -> [Result] {
        var results: [Result] = []
        let chunks = html.components(separatedBy: "class=\"b_algo\"").dropFirst()
        for chunk in chunks {
            let piece = chunk.components(separatedBy: "</li>").first ?? chunk
            guard let anchor = all(piece, "<h2[^>]*>\\s*<a[^>]*href=\"([^\"]+)\"[^>]*>(.*?)</a>").first else { continue }
            let url = unwrapBing(anchor[1])
            let title = plain(anchor[2])
            let snippet = plain(first(piece, "<p[^>]*>(.*?)</p>") ?? first(piece, "class=\"b_caption\"[^>]*>(.*?)</div>") ?? "")
            guard url.hasPrefix("http"), !title.isEmpty else { continue }
            results.append(Result(title: title, url: url, snippet: snippet))
        }
        return results
    }

    public static func duckResults(_ html: String) -> [Result] {
        var results: [Result] = []
        let chunks = html.components(separatedBy: "class=\"result__body").dropFirst()
        for chunk in chunks {
            guard let anchor = all(chunk, "class=\"result__a\"[^>]*href=\"([^\"]+)\"[^>]*>(.*?)</a>").first else { continue }
            var url = entities(anchor[1])
            if let wrapped = first(url, "[?&]uddg=([^&]+)"), let real = wrapped.removingPercentEncoding { url = real }
            if url.hasPrefix("//") { url = "https:" + url }
            let snippet = plain(first(chunk, "class=\"result__snippet\"[^>]*>(.*?)</a>") ?? "")
            let title = plain(anchor[2])
            guard url.hasPrefix("http"), !title.isEmpty else { continue }
            results.append(Result(title: title, url: url, snippet: snippet))
        }
        return results
    }

    /// Page bytes as text, in the page's own encoding (many Chinese sites still use GBK).
    public static func decode(_ data: Data, encodingName: String?) -> String {
        func encoding(_ name: String) -> String.Encoding? {
            let lower = name.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
            if lower.contains("utf-8") || lower.contains("utf8") { return .utf8 }
            if ["gb2312", "gbk", "gb18030", "x-gbk"].contains(lower) {
                return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
            }
            let cf = CFStringConvertIANACharSetNameToEncoding(lower as CFString)
            guard cf != kCFStringEncodingInvalidId else { return nil }
            return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
        }
        var name = encodingName
        if name == nil {
            let head = String(decoding: data.prefix(4096), as: UTF8.self)
            name = first(head, "<meta[^>]+charset=[\"']?([a-z0-9_-]+)")
        }
        if let name, let found = encoding(name), found != .utf8, let text = String(data: data, encoding: found) {
            return text
        }
        return String(decoding: data, as: UTF8.self)
    }
}

/// Fetches pages the way a browser would ask for them.
enum WebFetch {
    static let agent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    static func get(_ url: URL, timeout: TimeInterval = 20) async throws -> (data: Data, type: String?, encoding: String?, url: URL) {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue(agent, forHTTPHeaderField: "User-Agent")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.7", forHTTPHeaderField: "Accept-Language")
        request.setValue("text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        let (data, response) = try await HTTP.session.data(for: request)
        let http = response as? HTTPURLResponse
        if let status = http?.statusCode, !(200..<400).contains(status) {
            throw ProviderError(status: status, "网页打不开（\(status)）")
        }
        return (data, http?.mimeType, http?.textEncodingName, http?.url ?? url)
    }
}

/// Searches the web: Bing first, DuckDuckGo when Bing gives nothing.
public struct WebSearchTool: AgentTool {
    public init() {}

    public var spec: ToolSpec {
        ToolSpec(
            name: "web_search",
            description: "在网上搜索，返回标题、链接和摘要。查新闻、价格、天气、事实时用。摘要不够时再用 web_read 读原文。",
            parameters: [
                "type": "object",
                "properties": [
                    "query": ["type": "string", "description": "搜索词，简短，像人在搜索框里输入的那样"],
                ],
                "required": ["query"],
            ]
        )
    }

    public func label(for arguments: JSONValue) -> String {
        "搜索：\(arguments["query"]?.string ?? "")"
    }

    public func run(_ arguments: JSONValue) async throws -> ToolOutput {
        guard let query = arguments["query"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty else {
            return ToolOutput("没有给搜索词。", isError: true)
        }
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?#")
        let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed) ?? query
        var results: [WebText.Result] = []
        var failures: [String] = []
        for (address, parse) in [
            ("https://www.bing.com/search?q=\(encoded)&setlang=zh-Hans", WebText.bingResults),
            ("https://cn.bing.com/search?q=\(encoded)", WebText.bingResults),
            ("https://html.duckduckgo.com/html/?q=\(encoded)", WebText.duckResults),
        ] {
            guard let url = URL(string: address) else { continue }
            do {
                let page = try await WebFetch.get(url, timeout: 12)
                results = parse(WebText.decode(page.data, encodingName: page.encoding))
                if !results.isEmpty { break }
            } catch {
                failures.append(error.localizedDescription)
            }
        }
        guard !results.isEmpty else {
            return ToolOutput(failures.isEmpty ? "没有搜到结果。" : "搜索失败：\(failures.joined(separator: "；"))", isError: !failures.isEmpty)
        }
        let lines = results.prefix(8).enumerated().map { index, result in
            "\(index + 1). \(result.title)\n   \(result.url)\n   \(result.snippet)"
        }
        return ToolOutput(lines.joined(separator: "\n"))
    }
}

/// Reads one page as text.
public struct WebReadTool: AgentTool {
    public var limit: Int

    public init(limit: Int = 14000) { self.limit = limit }

    public var spec: ToolSpec {
        ToolSpec(
            name: "web_read",
            description: "打开一个网址，读出网页正文。用来读搜索结果的原文、用户发来的链接。",
            parameters: [
                "type": "object",
                "properties": ["url": ["type": "string", "description": "完整网址，以 http 或 https 开头"]],
                "required": ["url"],
            ]
        )
    }

    public func label(for arguments: JSONValue) -> String {
        let address = arguments["url"]?.string ?? ""
        return "读网页：\(URL(string: address)?.host ?? address)"
    }

    public func run(_ arguments: JSONValue) async throws -> ToolOutput {
        var address = arguments["url"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !address.isEmpty, !address.contains("://") { address = "https://" + address }
        guard let url = URL(string: address), url.scheme?.hasPrefix("http") == true else {
            return ToolOutput("网址不对：\(address)", isError: true)
        }
        let page = try await WebFetch.get(url)
        let type = page.type ?? ""
        if type.contains("pdf") { return ToolOutput("这是 PDF，暂时读不了。", isError: true) }
        if type.hasPrefix("image/") || type.hasPrefix("video/") || type.hasPrefix("audio/") {
            return ToolOutput("这个链接是\(type)文件，不是网页。", isError: true)
        }
        let source = WebText.decode(page.data, encodingName: page.encoding)
        let isHTML = type.contains("html") || source.range(of: "<html", options: .caseInsensitive) != nil
        let content = isHTML ? WebText.page(source) : WebText.Page(title: "", text: source)
        var text = content.text
        if text.count > limit { text = String(text.prefix(limit)) + "\n……（后面还有，太长截断了）" }
        if text.isEmpty { text = "（这个网页没有读到正文，可能要登录或者靠脚本加载。）" }
        let heading = content.title.isEmpty ? page.url.absoluteString : "\(content.title)\n\(page.url.absoluteString)"
        return ToolOutput("\(heading)\n\n\(text)")
    }
}
