import AgentKit
import SwiftUI
import UIKit

/// A model a Bot can think with.
struct ModelInfo: Equatable, Identifiable {
    let ref: String
    var name: String?
    var providerName: String?
    var id: String { ref }
}

/// Something a Bot asked and is waiting on.
struct Question: Equatable {
    struct Option: Equatable { var label: String }

    let id: String
    var question: String?
    var detail: String?
    var options: [Option]?
    var multiSelect: Bool?
}

struct Approval: Identifiable, Equatable {
    struct Detail: Equatable {
        var text: String?
        var code: String?
    }

    let id: String
    var botId: String?
    var roomId: String?
    var chat: String?
    var tool: String?
    var reason: String?
    var detail: Detail?
    /// When it was asked, in milliseconds.
    var at: Double?
    var answerable: Bool?
}

/// What a chat hears while its Bot works.
enum TurnEvent {
    /// The kept messages changed: read them again.
    case changed
    /// More of the reply being written.
    case text(String)
    /// A tool started.
    case tool(String)
    case finished
    case failed(String)
}

struct TeamError: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}

/// The whole team, on this phone: Bots, chats, memory, and the turns running now.
@MainActor
final class TeamModel: ObservableObject {
    enum Phase: Equatable {
        /// No model service yet.
        case setup
        case ready
        case demo
    }

    @Published private(set) var phase: Phase = .setup
    @Published private(set) var bots: [BotInfo] = []
    @Published private(set) var rooms: [RoomInfo] = []
    @Published private(set) var approvals: [Approval] = []
    @Published private(set) var questions: [String: Question] = [:]
    @Published private(set) var memories: [Memory] = []
    @Published private(set) var settings = TeamSettings()
    /// What each chat's Bot is doing now, by chat key.
    @Published private(set) var doing: [String: String] = [:]
    /// Bots speaking in a group right now.
    @Published private(set) var busyBots: Set<String> = []

    private var entries: [String: [Entry]] = [:]
    private var runs: [String: (token: UUID, task: Task<Void, Never>)] = [:]
    private var waiters: [String: CheckedContinuation<Bool, Never>] = [:]
    private var feeds: [UUID: (key: String, handler: (TurnEvent) -> Void)] = [:]
    private var laters: [Later] = []
    private var labels: [String: String] = [:]

    init() { load() }

    static func key(bot id: String) -> String { "bot-\(id)" }
    static func key(room id: String) -> String { "room-\(id)" }

    var models: [ModelInfo] {
        settings.endpoints.flatMap { endpoint in
            endpoint.models.map { ModelInfo(ref: "\(endpoint.id)/\($0)", name: $0, providerName: endpoint.name) }
        }
    }

    var mainBotId: String? { settings.mainBotId ?? bots.first?.id }

    func isMain(_ bot: BotInfo) -> Bool { bot.id == mainBotId || bot.main == true }

    func isWorking(_ key: String) -> Bool { doing[key] != nil }

    // MARK: Keeping

    private func load() {
        settings = Disk.load(TeamSettings.self, "settings.json") ?? TeamSettings()
        bots = Disk.load([BotInfo].self, "bots.json") ?? []
        rooms = Disk.load([RoomInfo].self, "rooms.json") ?? []
        memories = Disk.load([Memory].self, "memory.json") ?? []
        laters = Disk.load([Later].self, "later.json") ?? []
        entries = [:]
        approvals = []
        phase = settings.endpoints.isEmpty ? .setup : .ready
        sortBots()
        deliverDue()
    }

    private var keeping: Bool { phase != .demo }
    private func saveSettings() { if keeping { Disk.save(settings, "settings.json") } }
    private func saveBots() { if keeping { Disk.save(bots, "bots.json") } }
    private func saveRooms() { if keeping { Disk.save(rooms, "rooms.json") } }
    private func saveMemory() { if keeping { Disk.save(memories, "memory.json") } }
    private func saveLaters() { if keeping { Disk.save(laters, "later.json") } }

    private func sortBots() {
        let main = mainBotId
        bots.sort { left, right in
            if (left.id == main) != (right.id == main) { return left.id == main }
            return (left.createdAt ?? 0) < (right.createdAt ?? 0)
        }
    }

    // MARK: Model services

    func apiKey(for endpoint: String) -> String? { Vault.load(String.self, key: "key-\(endpoint)") }

    func addEndpoint(_ endpoint: Endpoint, key: String) {
        settings.endpoints.removeAll { $0.id == endpoint.id }
        settings.endpoints.append(endpoint)
        Vault.save(key, as: "key-\(endpoint.id)")
        if resolve(settings.defaultModel) == nil, let pick = Self.preferred(endpoint) {
            settings.defaultModel = "\(endpoint.id)/\(pick)"
        }
        saveSettings()
        if phase == .setup { phase = .ready }
        ensureMainBot()
    }

    func removeEndpoint(_ id: String) {
        settings.endpoints.removeAll { $0.id == id }
        Vault.remove("key-\(id)")
        if resolve(settings.defaultModel) == nil {
            settings.defaultModel = settings.endpoints.first.flatMap { endpoint in Self.preferred(endpoint).map { "\(endpoint.id)/\($0)" } }
        }
        saveSettings()
    }

    func setDefaultModel(_ ref: String) {
        settings.defaultModel = ref
        saveSettings()
    }

    static func preferred(_ endpoint: Endpoint) -> String? {
        endpoint.models.first { $0 == "deepseek-chat" }
            ?? endpoint.models.first { $0.contains("sonnet") }
            ?? endpoint.models.first
    }

    /// The service and model a ref names; nil when it names none that is set up.
    func resolve(_ ref: String?) -> (endpoint: Endpoint, model: String)? {
        guard let ref, let slash = ref.firstIndex(of: "/") else { return nil }
        let id = String(ref[..<slash])
        let model = String(ref[ref.index(after: slash)...])
        guard let endpoint = settings.endpoints.first(where: { $0.id == id }), !model.isEmpty else { return nil }
        return (endpoint, model)
    }

    func modelTitle(_ ref: String?) -> String {
        guard let found = resolve(ref) else { return "没有设置" }
        return "\(found.model) · \(found.endpoint.name)"
    }

    // MARK: Bots and groups

    private func ensureMainBot() {
        guard bots.isEmpty else { return }
        bots = [BotInfo(id: UUID().uuidString, name: "团子", role: "你的贴身助理", color: "orange", main: true,
                        instructions: "温柔、机灵，有点小调皮。记性很好，会主动关心用户。", createdAt: Now.ms)]
        settings.mainBotId = bots[0].id
        saveSettings()
        saveBots()
    }

    func saveBot(id: String?, name: String, role: String, color: String, model: String? = nil, instructions: String? = nil) async throws {
        if let id, let index = bots.firstIndex(where: { $0.id == id }) {
            bots[index].name = name
            bots[index].role = role
            bots[index].color = color
            if let model { bots[index].model = model.isEmpty ? nil : model }
            if let instructions { bots[index].instructions = instructions }
        } else {
            bots.append(BotInfo(id: UUID().uuidString, name: name, role: role, color: color, instructions: instructions,
                                model: model?.isEmpty == false ? model : nil, createdAt: Now.ms))
        }
        withAnimation(.smooth(duration: 0.35)) { sortBots() }
        saveBots()
    }

    func deleteBot(_ id: String) async throws {
        guard bots.count > 1 else { throw TeamError(message: "至少要留一个 Bot。") }
        stop(Self.key(bot: id))
        withAnimation(.smooth(duration: 0.35)) {
            bots.removeAll { $0.id == id }
            for index in rooms.indices { rooms[index].members?.removeAll { $0 == id } }
        }
        if settings.mainBotId == id {
            settings.mainBotId = bots.first?.id
            saveSettings()
        }
        entries[Self.key(bot: id)] = nil
        if keeping { Disk.remove(Disk.chatFile(Self.key(bot: id))) }
        saveBots()
        saveRooms()
    }

    @discardableResult
    func createRoom(name: String, members: [String]) -> RoomInfo {
        let room = RoomInfo(id: UUID().uuidString, name: name, members: members, lastAt: Now.ms)
        withAnimation(.smooth(duration: 0.35)) { rooms.insert(room, at: 0) }
        saveRooms()
        return room
    }

    func deleteRoom(_ id: String) {
        stop(Self.key(room: id))
        withAnimation(.smooth(duration: 0.35)) { rooms.removeAll { $0.id == id } }
        entries[Self.key(room: id)] = nil
        if keeping { Disk.remove(Disk.chatFile(Self.key(room: id))) }
        saveRooms()
    }

    /// What a Bot is up to, in a few words, and the color of its light.
    func status(of bot: BotInfo) -> (text: String, light: Color) {
        if approvals.contains(where: { $0.botId == bot.id }) { return ("等你批准", Color(hex: 0xF5A623)) }
        if doing[Self.key(bot: bot.id)] != nil || busyBots.contains(bot.id) { return ("正在干活", Color(hex: 0x5B8DEF)) }
        if phase == .ready, resolve(bot.model ?? settings.defaultModel) == nil { return ("还没有模型", Color(hex: 0xF0616D)) }
        return ("空闲", Color(hex: 0x34C98A))
    }

    // MARK: Memory

    func remember(_ fact: String, by bot: String?) {
        guard !memories.contains(where: { $0.text == fact }) else { return }
        memories.append(Memory(id: UUID().uuidString, text: fact, at: Now.ms, by: bot))
        saveMemory()
    }

    func forget(about words: String) -> [String] {
        let needle = words.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        let gone = memories.filter { $0.text.localizedCaseInsensitiveContains(needle) }
        memories.removeAll { gone.contains($0) }
        saveMemory()
        return gone.map(\.text)
    }

    func deleteMemory(_ id: String) {
        memories.removeAll { $0.id == id }
        saveMemory()
    }

    // MARK: Chats

    func history(_ key: String) -> [Entry] {
        if let kept = entries[key] { return kept }
        let loaded = keeping ? (Disk.load([Entry].self, Disk.chatFile(key)) ?? []) : []
        entries[key] = loaded
        return loaded
    }

    private func append(_ entry: Entry, to key: String) {
        var list = history(key)
        list.append(entry)
        entries[key] = list
        if keeping { Disk.save(list, Disk.chatFile(key)) }
        notify(key, .changed)
    }

    func listen(_ key: String, _ handler: @escaping (TurnEvent) -> Void) -> UUID {
        let id = UUID()
        feeds[id] = (key, handler)
        return id
    }

    func unlisten(_ id: UUID) { feeds[id] = nil }

    private func notify(_ key: String, _ event: TurnEvent) {
        for feed in feeds.values where feed.key == key { feed.handler(event) }
    }

    /// The chat's last words go on the home screen.
    private func touch(_ key: String, preview: String?, speaker: String? = nil) {
        let now = Now.ms
        let line = preview.map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120)) }
        if key.hasPrefix("bot-"), let index = bots.firstIndex(where: { Self.key(bot: $0.id) == key }) {
            bots[index].lastAt = now
            if let line, !line.isEmpty { bots[index].preview = line }
            saveBots()
        } else if let index = rooms.firstIndex(where: { Self.key(room: $0.id) == key }) {
            rooms[index].lastAt = now
            if let line, !line.isEmpty {
                let name = speaker.flatMap { id in bots.first { $0.id == id }?.name }
                rooms[index].preview = name.map { "\($0)：\(line)" } ?? line
            }
            let room = rooms.remove(at: index)
            rooms.insert(room, at: 0)
            saveRooms()
        }
    }

    func send(_ text: String, photos: [Data], to key: String) {
        guard phase != .demo else { return }
        let names = keeping ? photos.map(Disk.keepPhoto) : []
        append(Entry(id: UUID().uuidString, at: Now.ms, message: .user(text), photos: names), to: key)
        touch(key, preview: nil)
        start(key)
    }

    func stop(_ key: String) {
        for approval in approvals where approval.chat == key {
            if let waiter = waiters.removeValue(forKey: approval.id) { waiter.resume(returning: false) }
        }
        withAnimation(.smooth) { approvals.removeAll { $0.chat == key } }
        runs[key]?.task.cancel()
    }

    private func start(_ key: String) {
        let previous = runs[key]?.task
        stop(key)
        let token = UUID()
        doing[key] = "正在想"
        let task = Task { [weak self] in
            await previous?.value
            await self?.run(key, token: token)
        }
        runs[key] = (token, task)
    }

    private func run(_ key: String, token: UUID) async {
        let grace = UIApplication.shared.beginBackgroundTask(withName: "bot-turn")
        if key.hasPrefix("room-") {
            if let room = rooms.first(where: { Self.key(room: $0.id) == key }) {
                for member in (room.members ?? []).compactMap({ id in bots.first { $0.id == id } }) {
                    if Task.isCancelled { break }
                    busyBots.insert(member.id)
                    let going = await turn(member, in: key, room: room)
                    busyBots.remove(member.id)
                    if !going { break }
                }
            }
        } else if let bot = bots.first(where: { Self.key(bot: $0.id) == key }) {
            await turn(bot, in: key, room: nil)
        }
        if runs[key]?.token == token {
            runs[key] = nil
            doing[key] = nil
        }
        notify(key, .finished)
        if grace != .invalid { UIApplication.shared.endBackgroundTask(grace) }
    }

    /// One Bot speaks once. False when the group should not go on.
    @discardableResult
    private func turn(_ bot: BotInfo, in key: String, room: RoomInfo?) async -> Bool {
        guard let found = resolve(bot.model ?? settings.defaultModel) ?? resolve(settings.defaultModel) else {
            fail(key, "还没有可用的模型。到 设置 → 模型 里加一个。")
            return false
        }
        let endpoint = found.endpoint
        guard let apiKey = apiKey(for: endpoint.id), !apiKey.isEmpty else {
            fail(key, "\(endpoint.name) 的密钥找不到了，请到设置里重新填一次。")
            return false
        }
        let messages = context(for: key, bot: bot, room: room, vision: endpoint.vision != false)
        guard messages.contains(where: { $0.role == .user }) else { return false }
        let botId = bot.id
        let speaker = room == nil ? nil : botId
        let agent = Agent(
            provider: endpoint.provider(key: apiKey),
            model: found.model,
            system: system(for: bot, room: room),
            tools: tools(for: bot, key: key),
            approve: { [weak self] ask, _ in await self?.ask(ask, bot: botId, chat: key) ?? false }
        )
        doing[key] = room == nil ? "正在想" : "\(bot.name)在想"
        do {
            try await agent.run(history: messages) { [weak self] event in
                await self?.hear(event, chat: key, speaker: speaker)
            }
            if UIApplication.shared.applicationState != .active,
               let last = history(key).last(where: { $0.message.role == .assistant && !$0.message.text.isEmpty }) {
                Notify.now(bot.name, last.message.text, chat: key)
            }
            return true
        } catch is CancellationError {
            append(Entry(id: UUID().uuidString, at: Now.ms, message: .assistant("（被你叫停了）"), note: true), to: key)
            return false
        } catch {
            fail(key, "没回成：\(error.localizedDescription)")
            return false
        }
    }

    private func fail(_ key: String, _ text: String) {
        append(Entry(id: UUID().uuidString, at: Now.ms, message: .assistant(text), note: true), to: key)
        notify(key, .failed(text))
    }

    private func hear(_ event: AgentEvent, chat key: String, speaker: String?) {
        switch event {
        case .text(let piece):
            if doing[key] != "正在回复" { doing[key] = "正在回复" }
            notify(key, .text(piece))
        case .reasoning:
            if doing[key] != "正在想" { doing[key] = "正在想" }
        case .toolStarted(let id, _, let label):
            labels[id] = label
            doing[key] = label
            notify(key, .tool(label))
        case .toolFinished:
            break
        case .message(let message):
            var kept = message
            var label: String?
            if message.role == .tool {
                label = message.toolCallId.flatMap { labels.removeValue(forKey: $0) }
                // The model had all of it in this turn; later turns need only the gist.
                if kept.text.count > 3000 { kept.text = String(kept.text.prefix(3000)) + "\n……" }
            }
            append(Entry(id: UUID().uuidString, at: Now.ms, message: kept, speaker: speaker, label: label), to: key)
            if message.role == .assistant, !message.text.isEmpty { touch(key, preview: message.text, speaker: speaker) }
        case .usage:
            break
        }
    }

    /// The chat as the model reads it: the newest part, starting at a user message, with photos where they help.
    private func context(for key: String, bot: BotInfo, room: RoomInfo?, vision: Bool) -> [Message] {
        let all = history(key).filter { $0.note != true }
        var start = all.count
        var size = 0
        while start > 0 {
            let entry = all[start - 1]
            size += entry.message.text.count + entry.message.toolCalls.reduce(0) { $0 + $1.arguments.count }
            if size > 48_000, start < all.count - 1 { break }
            start -= 1
        }
        while start < all.count, all[start].message.role != .user { start += 1 }
        let recent = Array(all[start...])
        let photoEntries = Set(recent.filter { !$0.photos.isEmpty }.suffix(3).map(\.id))
        var messages: [Message] = []
        for entry in recent {
            var message = entry.message
            if room != nil {
                if message.role == .assistant, entry.speaker != bot.id {
                    guard !message.text.isEmpty else { continue }
                    let name = bots.first { $0.id == entry.speaker }?.name ?? "另一个 Bot"
                    messages.append(.user("【\(name)】\(message.text)"))
                    continue
                }
                if message.role == .tool, entry.speaker != bot.id { continue }
                if message.role == .user { message.text = "【用户】\(message.text)" }
            }
            if !entry.photos.isEmpty {
                if vision, photoEntries.contains(entry.id) {
                    message.images = entry.photos.compactMap { Disk.photo($0).map { ImagePart(data: $0) } }
                } else {
                    message.text += "\n［发了 \(entry.photos.count) 张图片\(vision ? "，已经看过" : "，你现在用的模型看不了图")］"
                }
            }
            messages.append(message)
        }
        return Self.paired(messages)
    }

    /// Every tool call gets its answer, even one cut off when a turn was stopped.
    static func paired(_ messages: [Message]) -> [Message] {
        var out: [Message] = []
        var index = 0
        while index < messages.count {
            let message = messages[index]
            out.append(message)
            index += 1
            guard message.role == .assistant, !message.toolCalls.isEmpty else { continue }
            var answered = Set<String>()
            while index < messages.count, messages[index].role == .tool {
                if let id = messages[index].toolCallId, message.toolCalls.contains(where: { $0.id == id }), !answered.contains(id) {
                    answered.insert(id)
                    out.append(messages[index])
                }
                index += 1
            }
            for call in message.toolCalls where !answered.contains(call.id) {
                out.append(.toolResult("（这一步没有完成）", for: call, isError: true))
            }
        }
        return out
    }

    private func system(for bot: BotInfo, room: RoomInfo?) -> String {
        var parts: [String] = []
        let role = (bot.role?.isEmpty == false) ? "，\(bot.role!)" : ""
        parts.append("你是「\(bot.name)」\(role)。你住在用户的 iPhone 里，是用户私人 Bot 团队的一员。")
        if let instructions = bot.instructions?.trimmingCharacters(in: .whitespacesAndNewlines), !instructions.isEmpty {
            parts.append("你的设定：\(instructions)")
        }
        let others = bots.filter { $0.id != bot.id }.map { other in
            other.role?.isEmpty == false ? "\(other.name)（\(other.role!)）" : other.name
        }
        if !others.isEmpty { parts.append("团队里还有：\(others.joined(separator: "、"))。") }
        if let room {
            let names = (room.members ?? []).compactMap { id in bots.first { $0.id == id }?.name }
            parts.append("现在是群聊「\(room.name)」，成员有用户和 \(names.joined(separator: "、"))。用户和其他 Bot 的话以【名字】开头。你只说你自己的部分：不要替别人说话，不要在开头写自己的名字，别人说过的不重复；没什么要补充就简短回应。")
        }
        parts.append("现在是 \(When.show(Date()))，\(TimeZone.current.identifier)。")
        if !memories.isEmpty {
            parts.append("你记得的关于用户的事：\n" + memories.map { "- \($0.text)" }.joined(separator: "\n"))
        }
        parts.append("""
        说话：中文，口语，亲切自然，像熟悉的朋友聊天。先说结论，能短就短；内容多时再分点。不说客套话。
        做事：
        - 要最新的信息（新闻、价格、天气、事实），先用 web_search 搜，再用 web_read 读原文核实，回答末尾附上来源链接。
        - 用户说起关于自己的、以后用得上的事，用 remember 记下；一次性的小事不记。
        - 日程、提醒、到点找用户，用对应的工具，时间都用本地时间。
        - 不确定就直说，不要编。
        """)
        return parts.joined(separator: "\n\n")
    }

    private func tools(for bot: BotInfo, key: String) -> [AgentTool] {
        let botId = bot.id
        return [
            WebSearchTool(),
            WebReadTool(),
            RememberTool { [weak self] fact in await self?.remember(fact, by: botId) },
            ForgetTool { [weak self] about in await self?.forget(about: about) ?? [] },
            CalendarListTool(),
            CalendarAddTool(),
            RemindersListTool(),
            ReminderAddTool(),
            LaterTool(botName: bot.name) { [weak self] text, at in await self?.later(text, at: at, bot: botId, chat: key) },
        ]
    }

    // MARK: Approvals

    private func ask(_ ask: ApprovalAsk, bot: String, chat: String) async -> Bool {
        let id = UUID().uuidString
        let approval = Approval(
            id: id, botId: bot, roomId: chat.hasPrefix("room-") ? String(chat.dropFirst(5)) : nil, chat: chat,
            tool: ask.title, reason: ask.reason, detail: ask.detail.map { Approval.Detail(text: $0) },
            at: Now.ms, answerable: true
        )
        let before = doing[chat]
        doing[chat] = "等你批准"
        withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) { approvals.append(approval) }
        Haptics.tick(0.8)
        if UIApplication.shared.applicationState != .active {
            let name = bots.first { $0.id == bot }?.name ?? "Bot"
            Notify.now("\(name)在等你批准", "\(ask.title)：\(ask.reason)", chat: chat)
        }
        let allowed = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in waiters[id] = continuation }
        if doing[chat] == "等你批准" { doing[chat] = before }
        return allowed
    }

    /// Answers an approval: lets the Bot go ahead once, or turns it down.
    func answer(_ approval: Approval, allow: Bool) async throws {
        if phase == .demo {
            try? await Task.sleep(nanoseconds: 250_000_000)
            approvals.removeAll { $0.id == approval.id }
            return
        }
        guard let waiter = waiters.removeValue(forKey: approval.id) else {
            approvals.removeAll { $0.id == approval.id }
            throw TeamError(message: "这张单子已经不在了。")
        }
        approvals.removeAll { $0.id == approval.id }
        waiter.resume(returning: allow)
    }

    // MARK: Later

    private func later(_ text: String, at date: Date, bot: String, chat: String) {
        let item = Later(id: UUID().uuidString, chat: chat, botId: bot, text: text, at: date.timeIntervalSince1970)
        laters.append(item)
        saveLaters()
        Notify.schedule(item, from: bots.first { $0.id == bot }?.name ?? "Bot")
    }

    /// Messages whose time has come go into their chats.
    func deliverDue() {
        guard keeping else { return }
        let now = Date().timeIntervalSince1970
        let due = laters.filter { $0.at <= now }.sorted { $0.at < $1.at }
        guard !due.isEmpty else { return }
        laters.removeAll { item in due.contains { $0.id == item.id } }
        saveLaters()
        for item in due {
            let speaker = item.chat.hasPrefix("room-") ? item.botId : nil
            append(Entry(id: UUID().uuidString, at: item.at * 1000, message: .assistant(item.text), speaker: speaker), to: item.chat)
            touch(item.chat, preview: item.text, speaker: speaker)
        }
    }

    /// Called when the app comes back to the front.
    func wake() { deliverDue() }

    // MARK: Demo

    func showDemo() {
        phase = .demo
        bots = [
            BotInfo(id: "chief", name: "团子", role: "贴身助理", color: "orange", main: true, preview: "明早 8 点叫你起床，记得带伞哦", lastAt: Now.ms - 600_000),
            BotInfo(id: "scout", name: "小探", role: "查资料 · 逛网页", color: "magenta"),
            BotInfo(id: "writer", name: "墨墨", role: "写东西 · 改稿子", color: "violet"),
            BotInfo(id: "chef", name: "饭团", role: "吃什么 · 怎么做", color: "green"),
        ]
        settings.mainBotId = "chief"
        rooms = [RoomInfo(id: "trip", name: "周末去哪玩", preview: "小探：查到三个地方", members: ["chief", "scout"])]
        approvals = [
            Approval(id: "a1", botId: "chief", tool: "新建日程", reason: "周六 10:00  和朋友去磁器口", detail: .init(text: "提前 60 分钟提醒"), at: Now.ms, answerable: true),
            Approval(id: "a2", botId: "chef", tool: "添加提醒事项", reason: "今晚 18:30  泡黄豆", at: Now.ms, answerable: true),
        ]
        doing = [Self.key(bot: "scout"): "搜索：周末天气"]
    }

    func leaveDemo() {
        doing = [:]
        load()
    }
}
