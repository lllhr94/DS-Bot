import DSLink
import SwiftUI

/// One row of a chat.
struct ChatLine: Identifiable, Equatable {
    enum Kind { case user, bot, steps, note }
    enum Local { case sending, failed }

    var id: String
    var kind: Kind
    var text: String
    /// A steps row that is still running.
    var live = false
    /// Set on a message this phone sent that the computer has not shown back yet.
    var local: Local?
}

/// The chat with one Bot: reads it, keeps it live, sends into it.
@MainActor
final class ChatModel: ObservableObject {
    @Published private(set) var lines: [ChatLine] = []
    @Published private(set) var pending: [ChatLine] = []
    /// The reply as it is being written.
    @Published private(set) var streaming = ""
    @Published private(set) var loaded = false
    @Published private(set) var demoWorking = false
    @Published var error: String?

    let bot: BotInfo
    private let team: TeamModel
    private var sessionId: String
    private var feed: UUID?
    private var poll: Task<Void, Never>?
    private var demoReply: Task<Void, Never>?
    private var reading = false
    private var again = false
    private var attempts: [(id: String, text: String, done: Bool)] = []
    /// For each sent message, the rows the chat held when the computer took it.
    private var known: [String: Set<String>] = [:]

    private var demo: Bool { team.phase == .demo }

    init(bot: BotInfo, team: TeamModel) {
        self.bot = bot
        self.team = team
        sessionId = bot.sessionId ?? bot.id
    }

    func open() {
        guard feed == nil else { return }
        if demo {
            lines = Self.demoLines(for: bot)
            loaded = true
            return
        }
        feed = team.listen { [weak self] name, data in self?.hear(name, data) }
        poll = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(nanoseconds: 20_000_000_000)
            }
        }
    }

    func close() {
        if let feed { team.unlisten(feed) }
        feed = nil
        poll?.cancel()
        poll = nil
        demoReply?.cancel()
    }

    // MARK: Reading

    /// One read at a time; a burst of messages becomes one read and one more after it.
    func refresh() async {
        if demo { return }
        if reading { again = true; return }
        reading = true
        defer { reading = false }
        repeat {
            again = false
            do {
                let page = try await team.call("chat", ["botId": bot.id, "steps": true])
                if let id = page["sessionId"] as? String { sessionId = id }
                apply(Self.lines(from: page["items"] as? [Any] ?? []))
                loaded = true
            } catch let failure as LinkError {
                // Being offline is the link's state, shown on the home screen; the reconnect reads again.
                if failure.code != "link/offline", failure.code != "TRANSPORT_CLOSED" { error = "读不到对话：\(failure.message)" }
            } catch {
                self.error = "读不到对话，稍后会再试。"
            }
        } while again && !Task.isCancelled
    }

    private func apply(_ next: [ChatLine]) {
        let hadStream = !streaming.isEmpty
        // A finished reply stays on screen until the chat holds it, so nothing blinks.
        attempts.removeAll { $0.done }
        let nextStream = attempts.map(\.text).joined()
        let shown = pending.filter { local in
            guard let before = known[local.id] else { return false }
            return next.contains { $0.kind == .user && !before.contains($0.id) && Self.same($0.text, local.text) }
        }
        let nextPending = pending.filter { local in !shown.contains { $0.id == local.id } }
        for local in shown { known[local.id] = nil }
        let grew = next.count + nextPending.count > lines.count + pending.count
        let lastReply = lines.last(where: { $0.kind == .bot })?.id
        let newReply = loaded && next.last?.kind == .bot && next.last?.id != lastReply
        let change = {
            if self.lines != next { self.lines = next }
            if self.pending != nextPending { self.pending = nextPending }
            if self.streaming != nextStream { self.streaming = nextStream }
        }
        // The written-out reply takes the place of the streaming one in a single frame.
        if loaded && grew && !hadStream && shown.isEmpty {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) { change() }
        } else {
            change()
        }
        if newReply { Haptics.tick(0.6) }
    }

    private static func same(_ left: String, _ right: String) -> Bool {
        left.trimmingCharacters(in: .whitespacesAndNewlines) == right.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The computer's chat items as rows. Rows keep the same id when the chat grows.
    private static func lines(from items: [Any]) -> [ChatLine] {
        var seen: [String: Int] = [:]
        var out: [ChatLine] = []
        for case let item as [String: Any] in items {
            guard let kind = item["kind"] as? String else { continue }
            let order = (item["seq"] as? NSNumber)?.stringValue
                ?? (item["time"] as? NSNumber)?.stringValue
                ?? (kind == "steps" ? "t\((item["turn"] as? NSNumber)?.stringValue ?? "")" : "")
            let base = "\(kind)-\(order)"
            let count = seen[base, default: 0]
            seen[base] = count + 1
            let id = count == 0 ? base : "\(base)#\(count)"
            let text = (item["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            switch kind {
            case "user":
                let images = (item["images"] as? NSNumber)?.intValue ?? 0
                let shownText = images > 0 ? (text.isEmpty ? "［图片 ×\(images)］" : "\(text)\n［图片 ×\(images)］") : text
                if !shownText.isEmpty { out.append(ChatLine(id: id, kind: .user, text: shownText)) }
            case "bot":
                if !text.isEmpty { out.append(ChatLine(id: id, kind: .bot, text: text)) }
            case "steps":
                let tools = (item["tools"] as? [Any])?.count ?? 0
                let live = item["live"] as? Bool == true
                if tools > 0 || live {
                    out.append(ChatLine(id: id, kind: .steps, text: live ? (tools > 0 ? "正在干活，已做 \(tools) 步" : "正在干活") : "完成 \(tools) 步", live: live))
                }
            case "event", "divider":
                if !text.isEmpty { out.append(ChatLine(id: id, kind: .note, text: text)) }
            default:
                break
            }
        }
        return out
    }

    // MARK: Live events

    private func hear(_ name: String, _ data: [String: Any]) {
        guard data["sessionId"] as? String == sessionId else { return }
        switch name {
        case "message":
            Task { await refresh() }
        case "stream":
            let id = (data["attemptId"] as? String) ?? (data["attemptId"] as? NSNumber)?.stringValue ?? ""
            let phase = data["phase"] as? String
            if phase == "start" {
                attempts.removeAll { $0.id == id || $0.done }
                attempts.append((id, "", false))
            } else if let text = data["text"] as? String {
                if let index = attempts.firstIndex(where: { $0.id == id }) {
                    attempts[index].text += text
                } else {
                    attempts.append((id, text, false))
                }
            } else if phase == "end" {
                if let index = attempts.firstIndex(where: { $0.id == id }) { attempts[index].done = true }
                // The finished text normally leaves when the chat shows it; this is the fallback.
                Task { [weak self] in
                    await self?.refresh()
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                    self?.dropFinished()
                }
            }
            streaming = attempts.map(\.text).joined()
        default:
            break
        }
    }

    private func dropFinished() {
        guard attempts.contains(where: { $0.done }) else { return }
        attempts.removeAll { $0.done }
        streaming = attempts.map(\.text).joined()
    }

    // MARK: Sending

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        error = nil
        if demo { sendDemo(trimmed); return }
        let local = ChatLine(id: "local-\(UUID().uuidString)", kind: .user, text: trimmed, local: .sending)
        withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) { pending.append(local) }
        Task { await deliver(local.id) }
    }

    /// Tries a failed message again.
    func retry(_ id: String) {
        guard let index = pending.firstIndex(where: { $0.id == id }) else { return }
        pending[index].local = .sending
        error = nil
        Task { await deliver(id) }
    }

    func discard(_ id: String) {
        withAnimation(.smooth) { pending.removeAll { $0.id == id } }
        known[id] = nil
    }

    private func deliver(_ id: String) async {
        guard let local = pending.first(where: { $0.id == id }) else { return }
        do {
            _ = try await team.call("send", ["sessionId": sessionId, "text": local.text])
            known[id] = Set(lines.map(\.id))
            await refresh()
        } catch {
            if let index = pending.firstIndex(where: { $0.id == id }) {
                withAnimation(.smooth) { pending[index].local = .failed }
            }
            let code = (error as? LinkError)?.code
            self.error = code == "link/offline" || code == "TRANSPORT_CLOSED" || code == "RPC_TIMEOUT"
                ? "没发出去：还没连上电脑。"
                : "没发出去：\((error as? LinkError)?.message ?? "出错了")"
            Haptics.lock()
        }
    }

    func stop() {
        if demo {
            demoReply?.cancel()
            demoWorking = false
            return
        }
        Task { _ = try? await team.call("stop-chat", ["botId": bot.id]) }
    }

    // MARK: Demo

    private func sendDemo(_ text: String) {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) {
            lines.append(ChatLine(id: "demo-\(UUID().uuidString)", kind: .user, text: text))
        }
        demoReply?.cancel()
        demoReply = Task { [weak self] in
            self?.demoWorking = true
            try? await Task.sleep(nanoseconds: 900_000_000)
            let reply = "这是演示团队，我还没有连到真的电脑。扫码连上你的电脑之后，这里就是 Bot 真正的回答：它会一边想一边写，像现在这样一个字一个字出来。"
            for character in reply {
                if Task.isCancelled { break }
                self?.streaming.append(character)
                try? await Task.sleep(nanoseconds: 28_000_000)
            }
            guard let self else { return }
            let said = self.streaming
            self.streaming = ""
            if !said.isEmpty { self.lines.append(ChatLine(id: "demo-\(UUID().uuidString)", kind: .bot, text: said)) }
            self.demoWorking = false
            Haptics.tick(0.6)
        }
    }

    private static func demoLines(for bot: BotInfo) -> [ChatLine] {
        [
            ChatLine(id: "d1", kind: .user, text: "把这周的工作整理成周报，重点写上线进度"),
            ChatLine(id: "d2", kind: .steps, text: "完成 4 步"),
            ChatLine(id: "d3", kind: .bot, text: "周报写好了，分三部分：\n\n- **本周完成的事**\n- **上线进度和卡点**\n- 下周计划\n\n文件放在工作区的 `周报.md` 里。"),
        ]
    }
}
