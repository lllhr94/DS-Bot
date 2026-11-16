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
    /// In a group: the Bot that said it.
    var speaker: String?
    var speakerName: String?
    /// Photos picked on this phone, shown until the computer has them.
    var images: [Data] = []
}

/// The chat with one Bot: reads it, keeps it live, sends into it.
@MainActor
final class ChatModel: ObservableObject {
    @Published private(set) var lines: [ChatLine] = []
    @Published private(set) var pending: [ChatLine] = []
    /// The part of the reply being written that is on screen so far.
    @Published private(set) var streaming = ""
    /// The reply that just finished: the row that took over from the streaming one.
    @Published private(set) var fresh: Fresh?

    struct Fresh: Equatable {
        var id: String
        /// How many characters are out so far; nil once the whole reply is.
        var shown: Int?
    }
    @Published private(set) var loaded = false
    @Published private(set) var demoWorking = false
    @Published var error: String?

    /// The pages before the newest one, oldest first.
    @Published private(set) var earlier: [ChatLine] = []
    @Published private(set) var hasEarlier = false
    @Published private(set) var loadingEarlier = false

    /// The Bot this chat is with. For a group: a stand-in that carries the group's name.
    let bot: BotInfo
    /// Set when this is a group chat.
    let roomId: String?
    private let team: TeamModel
    private(set) var sessionId: String
    private var cursor: Any?
    /// How the computer will show each sent message back.
    private var echo: [String: String] = [:]
    private var feed: UUID?
    private var poll: Task<Void, Never>?
    private var demoReply: Task<Void, Never>?
    private var reading = false
    private var again = false
    private var attempts: [(id: String, text: String, done: Bool)] = []
    /// Everything received of the reply being written; `streaming` follows it at an even pace.
    private var target = ""
    private var shown = 0
    private var finalCount = 0
    private var typing: Task<Void, Never>?
    /// For each sent message, the rows the chat held when the computer took it.
    private var known: [String: Set<String>] = [:]

    private var demo: Bool { team.phase == .demo }

    init(bot: BotInfo, team: TeamModel) {
        self.bot = bot
        self.team = team
        roomId = nil
        sessionId = bot.sessionId ?? bot.id
    }

    init(room: RoomInfo, team: TeamModel) {
        let first = team.bots.first { $0.id == room.members?.first }
        bot = BotInfo(id: room.id, name: room.name, color: first?.color)
        self.team = team
        roomId = room.id
        sessionId = room.sessionId ?? room.id
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
        typing?.cancel()
        typing = nil
    }

    // MARK: Even pace

    /// Text arrives in bursts; this lets it out a little each frame, faster when more is waiting.
    private func type() {
        guard typing == nil else { return }
        typing = Task { [weak self] in
            while !Task.isCancelled, let self, self.step() {
                try? await Task.sleep(nanoseconds: 16_000_000)
            }
            self?.typing = nil
        }
    }

    /// Lets a few more characters out. False when there is nothing left to let out.
    private func step() -> Bool {
        if let settling = fresh, settling.shown != nil {
            guard shown < finalCount else {
                withAnimation(.easeOut(duration: 0.45)) { fresh?.shown = nil }
                return false
            }
            shown = min(finalCount, shown + max(1, (finalCount - shown) / 10))
            fresh?.shown = shown
            return true
        }
        let goal = target.count
        if shown > goal { shown = goal }
        guard shown < goal else { return false }
        shown = min(goal, shown + max(1, (goal - shown) / 10))
        streaming = String(target.prefix(shown))
        return true
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
                let page = try await read(cursor: nil)
                if let id = page["sessionId"] as? String { sessionId = id }
                if !loaded {
                    cursor = page["cursor"]
                    hasEarlier = cursor != nil && !(cursor is NSNull)
                }
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

    private func read(cursor: Any?) async throws -> [String: Any] {
        var payload: [String: Any] = ["steps": true]
        if let roomId { payload["roomId"] = roomId } else { payload["botId"] = bot.id }
        if let cursor { payload["cursor"] = cursor }
        return try await team.call(roomId == nil ? "chat" : "room-chat", payload)
    }

    /// Reads the page before the oldest one shown.
    func loadEarlier() async {
        guard hasEarlier, !loadingEarlier, let cursor, !(cursor is NSNull) else { return }
        loadingEarlier = true
        defer { loadingEarlier = false }
        guard let page = try? await read(cursor: cursor) else { return }
        self.cursor = page["cursor"]
        hasEarlier = self.cursor != nil && !(self.cursor is NSNull)
        let shown = Set((earlier + lines).map(\.id))
        let older = Self.lines(from: page["items"] as? [Any] ?? []).filter { !shown.contains($0.id) }
        earlier = older + earlier
    }

    private func apply(_ next: [ChatLine]) {
        let hadStream = !streaming.isEmpty
        let lastReply = lines.last(where: { $0.kind == .bot })?.id
        let reply = next.last(where: { $0.kind == .bot })
        let newReply = loaded && reply != nil && reply?.id != lastReply
        // A finished reply stays on screen until the chat holds it, so nothing blinks.
        if newReply { attempts.removeAll { $0.done } }
        target = attempts.map(\.text).joined()
        var nextStream = streaming
        var nextFresh = fresh
        if hadStream, target.isEmpty, newReply, let reply {
            // The written-out row takes over exactly where the streaming one stood.
            finalCount = reply.text.count
            nextFresh = Fresh(id: reply.id, shown: shown < finalCount ? shown : nil)
            nextStream = ""
        } else if target.isEmpty {
            nextStream = ""
        }
        let shownBack = pending.filter { local in
            guard let before = known[local.id] else { return false }
            return next.contains { $0.kind == .user && !before.contains($0.id) && Self.same($0.text, echo[local.id] ?? local.text) }
        }
        let nextPending = pending.filter { local in !shownBack.contains { $0.id == local.id } }
        for local in shownBack { known[local.id] = nil; echo[local.id] = nil }
        let grew = next.count + nextPending.count > lines.count + pending.count
        let change = {
            if self.lines != next { self.lines = next }
            if self.pending != nextPending { self.pending = nextPending }
            if self.streaming != nextStream { self.streaming = nextStream }
            if self.fresh != nextFresh { self.fresh = nextFresh }
        }
        if loaded && grew && !hadStream && shownBack.isEmpty {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) { change() }
        } else {
            change()
        }
        if nextFresh?.shown != nil { type() }
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
                let shownText = withPhotos(text, (item["images"] as? NSNumber)?.intValue ?? 0)
                if !shownText.isEmpty { out.append(ChatLine(id: id, kind: .user, text: shownText)) }
            case "bot":
                if !text.isEmpty {
                    out.append(ChatLine(id: id, kind: .bot, text: text, speaker: item["botId"] as? String, speakerName: item["name"] as? String))
                }
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

    /// A message's text with a note for the photos sent along.
    private static func withPhotos(_ text: String, _ count: Int) -> String {
        count > 0 ? (text.isEmpty ? "［图片 ×\(count)］" : "\(text)\n［图片 ×\(count)］") : text
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
                if attempts.count == 1 { shown = 0; fresh = nil }
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
            target = attempts.map(\.text).joined()
            if fresh?.shown != nil { fresh?.shown = nil }
            type()
        default:
            break
        }
    }

    private func dropFinished() {
        guard attempts.contains(where: { $0.done }) else { return }
        attempts.removeAll { $0.done }
        target = attempts.map(\.text).joined()
        if target.isEmpty { streaming = "" }
    }

    // MARK: Sending

    func send(_ text: String, photos: [Data] = []) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !photos.isEmpty else { return }
        error = nil
        if demo { sendDemo(Self.withPhotos(trimmed, photos.count)); return }
        var local = ChatLine(id: "local-\(UUID().uuidString)", kind: .user, text: trimmed, local: .sending)
        local.images = photos
        echo[local.id] = Self.withPhotos(trimmed, photos.count)
        let sent = local
        withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) { pending.append(sent) }
        Task { await deliver(sent.id) }
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
        echo[id] = nil
    }

    /// Answers the question a Bot asked in this chat.
    func answer(_ question: Question, selected: [String], custom: String) {
        error = nil
        Task {
            do {
                _ = try await team.call("answer-question", [
                    "sessionId": sessionId,
                    "questionId": question.id,
                    "answer": ["selected": selected, "custom": custom.trimmingCharacters(in: .whitespacesAndNewlines)],
                ])
                Haptics.tick(0.8)
                await refresh()
            } catch {
                self.error = "回答没送到，这个问题可能已经关了。"
                Haptics.lock()
            }
        }
    }

    private func deliver(_ id: String) async {
        guard let local = pending.first(where: { $0.id == id }) else { return }
        do {
            // Photos go up one by one first; the message then names them.
            var staged: [String] = []
            for photo in local.images {
                let answer = try await team.call("stage-image", ["mediaType": "image/jpeg", "data": photo.base64EncodedString()], timeout: 90)
                if let id = answer["id"] as? String { staged.append(id) }
            }
            var payload: [String: Any] = ["sessionId": sessionId, "text": local.text]
            if !staged.isEmpty { payload["images"] = staged }
            _ = try await team.call("send", payload, timeout: 60)
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
        Task {
            if let roomId {
                _ = try? await team.call("stop-room-work", ["roomId": roomId])
            } else {
                _ = try? await team.call("stop-chat", ["botId": bot.id])
            }
        }
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
            self?.shown = 0
            self?.fresh = nil
            // Bursts, the way a real computer sends them.
            var rest = Substring(reply)
            while !rest.isEmpty, !Task.isCancelled {
                let burst = rest.prefix(Int.random(in: 4...14))
                rest = rest.dropFirst(burst.count)
                self?.target.append(contentsOf: burst)
                self?.type()
                try? await Task.sleep(nanoseconds: 260_000_000)
            }
            guard let self else { return }
            let said = Task.isCancelled ? self.streaming : self.target
            self.target = ""
            if said.isEmpty {
                self.streaming = ""
            } else {
                let line = ChatLine(id: "demo-\(UUID().uuidString)", kind: .bot, text: said)
                self.finalCount = said.count
                self.lines.append(line)
                self.fresh = Fresh(id: line.id, shown: self.shown < said.count ? self.shown : nil)
                self.streaming = ""
                self.type()
            }
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
