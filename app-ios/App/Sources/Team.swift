import DSLink
import SwiftUI

struct BotInfo: Decodable, Identifiable, Equatable {
    struct Blocked: Decodable, Equatable { var code: String? }

    let id: String
    var name: String
    var role: String?
    var color: String?
    var main: Bool?
    var hidden: Bool?
    var pinned: Bool?
    var sessionId: String?
    var preview: String?
    var lastAt: Double?
    var blocked: Blocked?
    /// The model it thinks with, as the computer names it.
    var model: String?
}

/// A model the computer can give a Bot.
struct ModelInfo: Decodable, Equatable, Identifiable {
    let ref: String
    var name: String?
    var providerName: String?
    var id: String { ref }
}

struct RoomInfo: Decodable, Identifiable, Equatable {
    let id: String
    var name: String
    var preview: String?
    var members: [String]?
    var hidden: Bool?
    var lastAt: Double?
    var sessionId: String?
}

/// Something a Bot asked and is waiting on.
struct Question: Decodable, Equatable {
    struct Option: Decodable, Equatable { var label: String }

    let id: String
    var question: String?
    var detail: String?
    var options: [Option]?
    var multiSelect: Bool?
}

struct Approval: Decodable, Identifiable, Equatable {
    struct Detail: Decodable, Equatable {
        var text: String?
        var code: String?
    }

    let id: String
    var botId: String?
    var roomId: String?
    var sessionId: String?
    var tool: String?
    var reason: String?
    var detail: Detail?
    /// When it was asked, in milliseconds.
    var at: Double?
    /// False when only the computer can answer it.
    var answerable: Bool?
}

struct Work: Decodable, Equatable {
    struct Doing: Decodable, Equatable {
        var tool: String?
        var said: String?
        var note: String?
    }

    var bots: [String: Doing]?
    var approvals: [Approval]?
}

/// Decodes one piece of the team state and lets the rest stand when it does not fit.
private enum Loose {
    static func decode<Value: Decodable>(_ type: Value.Type, _ value: Any?) -> Value? {
        guard let value, JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

/// Keeps the link to the computer up and the team fresh.
@MainActor
final class TeamModel: ObservableObject {
    enum Phase: Equatable {
        case connecting
        case online
        case offline(String)
        /// The computer no longer knows this phone.
        case unpaired
        case demo
    }

    @Published private(set) var phase: Phase = .connecting
    @Published private(set) var bots: [BotInfo] = []
    @Published private(set) var rooms: [RoomInfo] = []
    @Published private(set) var work = Work()
    @Published private(set) var waitingForAnswer: Set<String> = []
    /// Open questions, by the chat they were asked in.
    @Published private(set) var questions: [String: Question] = [:]
    @Published private(set) var models: [ModelInfo] = []
    @Published private(set) var hostName = ""

    private var raw: [String: Any] = [:]
    private var revision = -1
    private var liveKey: String?
    private var mainBotId: String?
    private var loop: Task<Void, Never>?
    private var refreshing = false
    private var refreshAgain = false
    private var client: LinkClient?
    private var paired: (LinkIdentity, PairedHost)?
    private var feeds: [UUID: @MainActor (String, [String: Any]) -> Void] = [:]

    var approvals: [Approval] { work.approvals ?? [] }

    func start(identity: LinkIdentity, host: PairedHost) {
        stop()
        paired = (identity, host)
        hostName = host.name
        phase = .connecting
        connect(identity: identity, host: host)
    }

    /// Called when the app comes back to the front. iOS may have cut the link while the app
    /// slept without telling it, so this checks the link and starts a new one if it is dead.
    /// The team stays on screen meanwhile.
    func wake() {
        guard let paired, phase != .demo, phase != .unpaired, phase != .connecting else { return }
        let again = { [weak self] in
            guard let self else { return }
            self.loop?.cancel()
            self.client = nil
            // The computer sends the whole team to a new link.
            self.revision = -1
            self.liveKey = nil
            self.connect(identity: paired.0, host: paired.1)
        }
        guard client != nil else { again(); return }
        Task {
            do { _ = try await call("hello", [:], timeout: 5) } catch { again() }
        }
    }

    private func connect(identity: LinkIdentity, host: PairedHost) {
        loop = Task { [weak self] in
            var delay = 1.0
            while !Task.isCancelled {
                let client = LinkClient(identity: identity, host: host, hello: LinkHello(name: "iPhone"))
                do {
                    try await client.connect()
                    delay = 1
                    if let name = await client.hostName, !name.isEmpty { self?.hostName = name }
                    try await self?.run(client)
                    if !Task.isCancelled { self?.phase = .offline("连接断开了，正在重连") }
                } catch let error as LinkError {
                    if Task.isCancelled { break }
                    if error.code == "NOT_PAIRED" || error.code == "PAIRING_REJECTED" {
                        self?.phase = .unpaired
                        await client.close()
                        return
                    }
                    self?.phase = .offline(Self.explain(error))
                } catch {
                    if Task.isCancelled { break }
                    self?.phase = .offline("连接出错了，正在重试")
                }
                await client.close()
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                delay = min(delay * 2, 15)
            }
        }
    }

    /// Hears every event the computer sends (`message`, `stream`, …) until `unlisten`.
    func listen(_ handler: @escaping @MainActor (String, [String: Any]) -> Void) -> UUID {
        let id = UUID()
        feeds[id] = handler
        return id
    }

    func unlisten(_ id: UUID) { feeds[id] = nil }

    /// Runs one endpoint on the computer and returns its value.
    func call(_ endpoint: String, _ payload: [String: Any] = [:], timeout: TimeInterval = 30) async throws -> [String: Any] {
        guard let client else { throw LinkError("link/offline", "还没连上电脑。") }
        let params = try JSONSerialization.data(withJSONObject: ["endpoint": endpoint, "payload": payload])
        let data = try await client.call("bot", params: params, timeout: timeout)
        guard let answer = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        guard (answer["ok"] as? Bool) == true else {
            let failure = answer["error"] as? [String: Any]
            throw LinkError(failure?["code"] as? String ?? "HOST_ERROR", failure?["message"] as? String ?? "电脑报告了一个错误。")
        }
        return answer["value"] as? [String: Any] ?? [:]
    }

    /// Saves a Bot's name, role and color; `id` nil makes a new Bot.
    func saveBot(id: String?, name: String, role: String, color: String, model: String? = nil) async throws {
        if phase == .demo {
            if let index = bots.firstIndex(where: { $0.id == id }) {
                bots[index].name = name
                bots[index].role = role
                bots[index].color = color
            } else {
                bots.append(BotInfo(id: UUID().uuidString, name: name, role: role, color: color))
            }
            return
        }
        var payload: [String: Any] = ["name": name, "role": role, "color": color]
        if let id { payload["id"] = id }
        if let model { payload["model"] = model }
        _ = try await call(id == nil ? "create-bot" : "update-bot", payload, timeout: 60)
        if let client { await refreshSoon(client) }
    }

    func deleteBot(_ id: String) async throws {
        if phase == .demo {
            bots.removeAll { $0.id == id }
            return
        }
        _ = try await call("delete-bot", ["id": id], timeout: 60)
        if let client { await refreshSoon(client) }
    }

    /// Answers an approval: lets the Bot go ahead once, or turns it down.
    func answer(_ approval: Approval, allow: Bool) async throws {
        if phase == .demo {
            try? await Task.sleep(nanoseconds: 250_000_000)
            work.approvals?.removeAll { $0.id == approval.id }
            return
        }
        _ = try await call("approval-answer", ["id": approval.id, "choice": allow ? "allow" : "reject"])
    }

    func stop() {
        loop?.cancel()
        loop = nil
        client = nil
        paired = nil
        raw = [:]
        revision = -1
        liveKey = nil
        bots = []
        rooms = []
        work = Work()
        waitingForAnswer = []
        questions = [:]
    }

    private static func explain(_ error: LinkError) -> String {
        switch error.code {
        case "SERVER_UNREACHABLE", "TRANSPORT_CLOSED": return "连不上，正在重试"
        case "HOST_OFFLINE", "HOST_NOT_FOUND", "TARGET_OFFLINE": return "电脑不在线，正在等它"
        case "PEER_IDENTITY_MISMATCH": return "电脑的密钥变了，请重新配对"
        default: return "连接出错了（\(error.code)），正在重试"
        }
    }

    /// Runs one connection until it ends.
    private func run(_ client: LinkClient) async throws {
        revision = -1
        raw = [:]
        liveKey = nil
        try await refresh(client)
        self.client = client
        defer { if self.client === client { self.client = nil } }
        withAnimation(.smooth) { phase = .online }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in
                for await event in client.events { await self?.hear(event, from: client) }
            }
            // A slow poll stays as the fallback.
            group.addTask { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 15_000_000_000)
                    if Task.isCancelled { return }
                    await self?.refreshSoon(client)
                }
            }
            // The event stream ends when the connection does.
            _ = await group.next()
            group.cancelAll()
        }
    }

    /// Passes an event to the open screens. Only team changes read the team again, and
    /// never in line: a reply streaming in must not wait behind a team read.
    private func hear(_ event: LinkEvent, from client: LinkClient) {
        let data = (try? JSONSerialization.jsonObject(with: event.data)) as? [String: Any] ?? [:]
        for handler in feeds.values { handler(event.name, data) }
        if event.name != "stream" {
            Task { [weak self] in await self?.refreshSoon(client) }
        }
    }

    /// A burst of events becomes one read, and one more after it.
    private func refreshSoon(_ client: LinkClient) async {
        if refreshing { refreshAgain = true; return }
        refreshing = true
        defer { refreshing = false }
        repeat {
            refreshAgain = false
            try? await refresh(client)
        } while refreshAgain && !Task.isCancelled
    }

    private func refresh(_ client: LinkClient) async throws {
        var payload: [String: Any] = ["since": revision, "avatars": "ref"]
        if let liveKey { payload["live"] = liveKey }
        let params = try JSONSerialization.data(withJSONObject: ["endpoint": "state", "payload": payload])
        let data = try await client.call("bot", params: params)
        guard let answer = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        guard (answer["ok"] as? Bool) == true, let next = answer["value"] as? [String: Any] else {
            let failure = answer["error"] as? [String: Any]
            throw LinkError(failure?["code"] as? String ?? "HOST_ERROR", failure?["message"] as? String ?? "The computer reported an error.")
        }
        apply(next)
    }

    private func apply(_ next: [String: Any]) {
        let incoming = next["revision"] as? Int ?? 0
        // An older answer still in flight must not overwrite a newer one.
        guard incoming >= revision else { return }
        revision = incoming
        if let key = next["liveKey"] as? String { liveKey = key }
        if (next["unchanged"] as? Bool) == true, !raw.isEmpty {
            raw.merge(next) { _, new in new }
        } else {
            raw = next
        }
        mainBotId = raw["mainBotId"] as? String
        let main = mainBotId
        let nextBots = ((raw["bots"] as? [Any]) ?? [])
            .compactMap { Loose.decode(BotInfo.self, $0) }
            .filter { $0.hidden != true }
            .sorted { left, right in
                let leftMain = left.id == main || left.main == true
                let rightMain = right.id == main || right.main == true
                if leftMain != rightMain { return leftMain }
                if (left.pinned == true) != (right.pinned == true) { return left.pinned == true }
                return (left.lastAt ?? 0) > (right.lastAt ?? 0)
            }
        let nextRooms = ((raw["rooms"] as? [Any]) ?? [])
            .compactMap { Loose.decode(RoomInfo.self, $0) }
            .filter { $0.hidden != true }
        let nextWork = Loose.decode(Work.self, raw["work"]) ?? Work()
        let nextWaiting = Set((raw["questions"] as? [String: Any] ?? [:]).keys)
        let nextModels = ((raw["models"] as? [Any]) ?? []).compactMap { Loose.decode(ModelInfo.self, $0) }
        if nextModels != models { models = nextModels }
        let nextQuestions = (raw["questions"] as? [String: Any] ?? [:]).compactMapValues { Loose.decode(Question.self, $0) }
        withAnimation(.smooth(duration: 0.35)) {
            if nextBots != bots { bots = nextBots }
            if nextRooms != rooms { rooms = nextRooms }
            if nextWork != work { work = nextWork }
            if nextWaiting != waitingForAnswer { waitingForAnswer = nextWaiting }
            if nextQuestions != questions { questions = nextQuestions }
        }
    }

    func isMain(_ bot: BotInfo) -> Bool { bot.id == mainBotId || bot.main == true }

    /// What a Bot is up to, in a few words, and the color of its light.
    func status(of bot: BotInfo) -> (text: String, light: Color) {
        if bot.blocked != nil { return ("需要处理", Color(hex: 0xF0616D)) }
        if approvals.contains(where: { $0.botId == bot.id }) { return ("等你批准", Color(hex: 0xF5A623)) }
        if waitingForAnswer.contains(bot.sessionId ?? bot.id) { return ("等你回答", Color(hex: 0xF5A623)) }
        if work.bots?[bot.id] != nil { return ("正在干活", Color(hex: 0x5B8DEF)) }
        return ("空闲", Color(hex: 0x34C98A))
    }

    // MARK: Demo

    func showDemo() {
        stop()
        hostName = "演示"
        mainBotId = "chief"
        bots = [
            BotInfo(id: "chief", name: "主管", role: "分派任务 · 管理团队", color: "blue", main: true, preview: "周报写好了，放在工作区里"),
            BotInfo(id: "ops", name: "运维", role: "看服务 · 跑命令", color: "green"),
            BotInfo(id: "scout", name: "调研", role: "查资料 · 逛网页", color: "magenta"),
            BotInfo(id: "writer", name: "写手", role: "写文档 · 改稿子", color: "orange"),
        ]
        rooms = [RoomInfo(id: "launch", name: "上线准备", preview: "调研在查资料", members: ["chief", "scout"])]
        work = Work(
            bots: ["scout": Work.Doing(tool: "browser")],
            approvals: [
                Approval(id: "a1", botId: "ops", tool: "重启一个服务", reason: "网站响应变慢了，重启后应该恢复。", detail: .init(code: "systemctl restart nginx"), at: Date().timeIntervalSince1970 * 1000, answerable: true),
                Approval(id: "a2", botId: "writer", tool: "把周报发到团队邮箱", reason: "周报已经写完，等你确认后发出。", at: Date().timeIntervalSince1970 * 1000, answerable: true),
            ]
        )
        phase = .demo
    }
}
