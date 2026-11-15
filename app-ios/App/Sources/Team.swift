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
}

struct RoomInfo: Decodable, Identifiable, Equatable {
    let id: String
    var name: String
    var preview: String?
    var members: [String]?
    var hidden: Bool?
    var lastAt: Double?
}

struct Approval: Decodable, Identifiable, Equatable {
    let id: String
    var botId: String?
    var roomId: String?
    var tool: String?
    var reason: String?
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
    @Published private(set) var hostName = ""

    private var raw: [String: Any] = [:]
    private var revision = -1
    private var liveKey: String?
    private var mainBotId: String?
    private var loop: Task<Void, Never>?
    private var refreshing = false
    private var refreshAgain = false

    var approvals: [Approval] { work.approvals ?? [] }

    func start(identity: LinkIdentity, host: PairedHost) {
        stop()
        hostName = host.name
        phase = .connecting
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

    func stop() {
        loop?.cancel()
        loop = nil
        raw = [:]
        revision = -1
        liveKey = nil
        bots = []
        rooms = []
        work = Work()
        waitingForAnswer = []
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
        withAnimation(.smooth) { phase = .online }
        await withTaskGroup(of: Void.self) { group in
            // Every event from the computer means something moved: read the team again.
            group.addTask { [weak self] in
                for await _ in client.events { await self?.refreshSoon(client) }
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
        withAnimation(.smooth(duration: 0.35)) {
            if nextBots != bots { bots = nextBots }
            if nextRooms != rooms { rooms = nextRooms }
            if nextWork != work { work = nextWork }
            if nextWaiting != waitingForAnswer { waitingForAnswer = nextWaiting }
        }
    }

    func isMain(_ bot: BotInfo) -> Bool { bot.id == mainBotId || bot.main == true }

    /// What a Bot is up to, in a few words, and the color of its light.
    func status(of bot: BotInfo) -> (text: String, light: Color) {
        if bot.blocked != nil { return ("需要处理", Color(hex: 0xFF9A8F)) }
        if approvals.contains(where: { $0.botId == bot.id }) { return ("等你批准", Color(hex: 0xFFD98A)) }
        if waitingForAnswer.contains(bot.sessionId ?? bot.id) { return ("等你回答", Color(hex: 0xFFD98A)) }
        if work.bots?[bot.id] != nil { return ("正在干活", .white) }
        return ("空闲", Color(hex: 0x7CF0B8))
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
            approvals: [Approval(id: "a1", botId: "ops", tool: "shell", reason: "重启一个服务")]
        )
        phase = .demo
    }
}
