import AgentKit
import EventKit
import Foundation
import UserNotifications

/// Dates as the model writes them: local time, `2026-11-17 15:00` and the like.
enum When {
    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = format
        return formatter
    }

    private static let formats = [
        "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm",
        "yyyy/MM/dd HH:mm", "yyyy-MM-dd",
    ].map { When.formatter($0) }

    static func parse(_ text: String?) -> (date: Date, allDay: Bool)? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        for options: ISO8601DateFormatter.Options in [[.withInternetDateTime], [.withInternetDateTime, .withFractionalSeconds]] {
            iso.formatOptions = options
            if let date = iso.date(from: text) { return (date, false) }
        }
        for formatter in formats {
            if let date = formatter.date(from: text) { return (date, formatter.dateFormat == "yyyy-MM-dd") }
        }
        return nil
    }

    static func show(_ date: Date, time: Bool = true) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = time ? "M月d日 EEE HH:mm" : "M月d日 EEE"
        return formatter.string(from: date)
    }

    static func stamp(_ date: Date) -> String {
        formatter("yyyy-MM-dd HH:mm").string(from: date)
    }
}

private let dateHint = "本地时间，格式 2026-11-17 15:00；全天写 2026-11-17"

/// The phone's own calendar and reminders.
final class Organizer: @unchecked Sendable {
    static let shared = Organizer()
    let store = EKEventStore()

    func events() async throws {
        guard try await store.requestFullAccessToEvents() else {
            throw ProviderError("没有日历权限。请在 设置 → 隐私与安全性 → 日历 里允许。")
        }
    }

    func reminders() async throws {
        guard try await store.requestFullAccessToReminders() else {
            throw ProviderError("没有提醒事项权限。请在 设置 → 隐私与安全性 → 提醒事项 里允许。")
        }
    }
}

struct CalendarListTool: AgentTool {
    var spec: ToolSpec {
        ToolSpec(name: "calendar_events", description: "看用户系统日历里的日程。", parameters: [
            "type": "object",
            "properties": [
                "from": ["type": "string", "description": "从哪天开始，\(dateHint)。不写就是今天"],
                "days": ["type": "number", "description": "看几天，默认 7"],
            ],
        ])
    }

    func label(for arguments: JSONValue) -> String { "看日历" }

    func run(_ arguments: JSONValue) async throws -> ToolOutput {
        let organizer = Organizer.shared
        try await organizer.events()
        let start = Calendar.current.startOfDay(for: When.parse(arguments["from"]?.string)?.date ?? Date())
        let days = max(1, min(62, Int(arguments["days"]?.number ?? 7)))
        let end = Calendar.current.date(byAdding: .day, value: days, to: start) ?? start
        let predicate = organizer.store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = organizer.store.events(matching: predicate).sorted { $0.startDate < $1.startDate }
        guard !events.isEmpty else { return ToolOutput("\(When.show(start, time: false)) 起 \(days) 天里没有日程。") }
        let lines = events.prefix(80).map { event -> String in
            var line = event.isAllDay
                ? "\(When.show(event.startDate, time: false)) 全天 \(event.title ?? "")"
                : "\(When.show(event.startDate))–\(When.stamp(event.endDate).suffix(5)) \(event.title ?? "")"
            if let location = event.location, !location.isEmpty { line += " @\(location)" }
            return line
        }
        return ToolOutput(lines.joined(separator: "\n"))
    }
}

struct CalendarAddTool: AgentTool {
    var spec: ToolSpec {
        ToolSpec(name: "calendar_add", description: "在用户的系统日历里新建一个日程。会先请用户批准。", parameters: [
            "type": "object",
            "properties": [
                "title": ["type": "string"],
                "start": ["type": "string", "description": .string(dateHint)],
                "end": ["type": "string", "description": "结束时间，不写就是一小时后"],
                "location": ["type": "string"],
                "notes": ["type": "string"],
                "alert_minutes": ["type": "number", "description": "提前几分钟提醒，不写就不提醒"],
            ],
            "required": ["title", "start"],
        ])
    }

    func label(for arguments: JSONValue) -> String { "新建日程：\(arguments["title"]?.string ?? "")" }

    func approval(for arguments: JSONValue) -> ApprovalAsk? {
        let title = arguments["title"]?.string ?? ""
        let when = When.parse(arguments["start"]?.string).map { When.show($0.date, time: !$0.allDay) } ?? (arguments["start"]?.string ?? "")
        var detail = [String]()
        if let place = arguments["location"]?.string, !place.isEmpty { detail.append("地点：\(place)") }
        if let minutes = arguments["alert_minutes"]?.number { detail.append("提前 \(Int(minutes)) 分钟提醒") }
        return ApprovalAsk(title: "新建日程", reason: "\(when)  \(title)", detail: detail.isEmpty ? nil : detail.joined(separator: "\n"))
    }

    func run(_ arguments: JSONValue) async throws -> ToolOutput {
        guard let title = arguments["title"]?.string, !title.isEmpty, let start = When.parse(arguments["start"]?.string) else {
            return ToolOutput("缺标题或开始时间，或时间格式不对（\(dateHint)）。", isError: true)
        }
        let organizer = Organizer.shared
        try await organizer.events()
        let event = EKEvent(eventStore: organizer.store)
        event.title = title
        event.startDate = start.date
        event.isAllDay = start.allDay
        event.endDate = When.parse(arguments["end"]?.string)?.date ?? start.date.addingTimeInterval(start.allDay ? 86400 : 3600)
        event.location = arguments["location"]?.string
        event.notes = arguments["notes"]?.string
        if let minutes = arguments["alert_minutes"]?.number { event.addAlarm(EKAlarm(relativeOffset: -minutes * 60)) }
        event.calendar = organizer.store.defaultCalendarForNewEvents
        try organizer.store.save(event, span: .thisEvent, commit: true)
        return ToolOutput("已加进日历：\(When.show(start.date, time: !start.allDay)) \(title)")
    }
}

struct RemindersListTool: AgentTool {
    var spec: ToolSpec {
        ToolSpec(name: "reminders", description: "看用户系统「提醒事项」里还没完成的事。", parameters: ["type": "object", "properties": [:]])
    }

    func label(for arguments: JSONValue) -> String { "看提醒事项" }

    func run(_ arguments: JSONValue) async throws -> ToolOutput {
        let organizer = Organizer.shared
        try await organizer.reminders()
        let predicate = organizer.store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        let items: [(String, Date?)] = await withCheckedContinuation { continuation in
            organizer.store.fetchReminders(matching: predicate) { found in
                continuation.resume(returning: (found ?? []).map { ($0.title ?? "", $0.dueDateComponents?.date) })
            }
        }
        guard !items.isEmpty else { return ToolOutput("没有未完成的提醒事项。") }
        let sorted = items.sorted { ($0.1 ?? .distantFuture) < ($1.1 ?? .distantFuture) }
        return ToolOutput(sorted.prefix(60).map { title, due in due.map { "\(When.show($0)) \(title)" } ?? title }.joined(separator: "\n"))
    }
}

struct ReminderAddTool: AgentTool {
    var spec: ToolSpec {
        ToolSpec(name: "reminder_add", description: "在用户的「提醒事项」里加一条，可带到期时间（到时手机会提醒）。会先请用户批准。", parameters: [
            "type": "object",
            "properties": [
                "title": ["type": "string"],
                "due": ["type": "string", "description": "到期时间，\(dateHint)。不写就没有时间"],
                "notes": ["type": "string"],
            ],
            "required": ["title"],
        ])
    }

    func label(for arguments: JSONValue) -> String { "加提醒：\(arguments["title"]?.string ?? "")" }

    func approval(for arguments: JSONValue) -> ApprovalAsk? {
        let due = When.parse(arguments["due"]?.string).map { When.show($0.date, time: !$0.allDay) }
        return ApprovalAsk(title: "添加提醒事项", reason: [due, arguments["title"]?.string].compactMap { $0 }.joined(separator: "  "))
    }

    func run(_ arguments: JSONValue) async throws -> ToolOutput {
        guard let title = arguments["title"]?.string, !title.isEmpty else { return ToolOutput("缺标题。", isError: true) }
        let organizer = Organizer.shared
        try await organizer.reminders()
        let reminder = EKReminder(eventStore: organizer.store)
        reminder.title = title
        reminder.notes = arguments["notes"]?.string
        reminder.calendar = organizer.store.defaultCalendarForNewReminders()
        if let due = When.parse(arguments["due"]?.string) {
            let parts: Set<Calendar.Component> = due.allDay ? [.year, .month, .day] : [.year, .month, .day, .hour, .minute]
            reminder.dueDateComponents = Calendar.current.dateComponents(parts, from: due.date)
            if !due.allDay { reminder.addAlarm(EKAlarm(absoluteDate: due.date)) }
        }
        try organizer.store.save(reminder, commit: true)
        return ToolOutput("已加进提醒事项：\(title)")
    }
}

/// The Bot writes down what the user tells it about themselves.
struct RememberTool: AgentTool {
    let keep: @Sendable (String) async -> Void

    var spec: ToolSpec {
        ToolSpec(name: "remember", description: "记下关于用户的一件事（喜好、习惯、身边的人、正在做的事），以后每次聊天都会看到。只记用户亲口说的、以后用得上的；一次一件事，写成一句完整的话。", parameters: [
            "type": "object",
            "properties": ["fact": ["type": "string", "description": "比如：用户是重庆人，喜欢吃辣"]],
            "required": ["fact"],
        ])
    }

    func label(for arguments: JSONValue) -> String { "记住：\(arguments["fact"]?.string ?? "")" }

    func run(_ arguments: JSONValue) async throws -> ToolOutput {
        guard let fact = arguments["fact"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !fact.isEmpty else {
            return ToolOutput("没写要记什么。", isError: true)
        }
        await keep(fact)
        return ToolOutput("记下了。")
    }
}

struct ForgetTool: AgentTool {
    let drop: @Sendable (String) async -> [String]

    var spec: ToolSpec {
        ToolSpec(name: "forget", description: "用户要你忘掉某件事，或者记的事已经不对了时，删掉相关的记忆。", parameters: [
            "type": "object",
            "properties": ["about": ["type": "string", "description": "要删的记忆里的关键词"]],
            "required": ["about"],
        ])
    }

    func label(for arguments: JSONValue) -> String { "忘掉：\(arguments["about"]?.string ?? "")" }

    func run(_ arguments: JSONValue) async throws -> ToolOutput {
        let about = arguments["about"]?.string ?? ""
        let gone = await drop(about)
        return ToolOutput(gone.isEmpty ? "没找到和「\(about)」有关的记忆。" : "删掉了：\n" + gone.joined(separator: "\n"))
    }
}

/// A message the Bot sends the user later, as a notification.
struct LaterTool: AgentTool {
    let botName: String
    let keep: @Sendable (String, Date) async -> Void

    var spec: ToolSpec {
        ToolSpec(name: "message_later", description: "到某个时间主动给用户发一条消息（手机会弹通知）。用户让你到点提醒、叫醒、问候时用；也可以在约好的事之前主动关心一下。", parameters: [
            "type": "object",
            "properties": [
                "at": ["type": "string", "description": "什么时候发，\(dateHint)"],
                "text": ["type": "string", "description": "到时候要说的话，用你自己的口吻"],
            ],
            "required": ["at", "text"],
        ])
    }

    func label(for arguments: JSONValue) -> String {
        let when = When.parse(arguments["at"]?.string).map { When.show($0.date) } ?? ""
        return "约好 \(when) 找你"
    }

    func run(_ arguments: JSONValue) async throws -> ToolOutput {
        guard let text = arguments["text"]?.string, !text.isEmpty, let at = When.parse(arguments["at"]?.string)?.date else {
            return ToolOutput("缺时间或内容，或时间格式不对（\(dateHint)）。", isError: true)
        }
        guard at > Date().addingTimeInterval(20) else { return ToolOutput("这个时间已经过了。", isError: true) }
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) == true else {
            return ToolOutput("用户没开通知权限，到时候没法提醒。请在 设置 → 通知 里打开。", isError: true)
        }
        await keep(text, at)
        return ToolOutput("好，\(When.show(at)) 会发给用户。")
    }
}

enum Notify {
    /// Schedules the notification for a message set for later.
    static func schedule(_ later: Later, from name: String) {
        let content = UNMutableNotificationContent()
        content.title = name
        content.body = later.text
        content.sound = .default
        content.userInfo = ["chat": later.chat]
        let date = Date(timeIntervalSince1970: later.at)
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: later.id, content: content, trigger: trigger))
    }

    /// A Bot finished while the app was away.
    static func now(_ title: String, _ body: String, chat: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = String(body.prefix(180))
        content.sound = .default
        content.userInfo = ["chat": chat]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
