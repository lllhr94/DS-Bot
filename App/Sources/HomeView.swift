import SwiftUI

struct HomeView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var team: TeamModel

    @State private var shown = false
    @State private var poked: String?
    @State private var opened: BotInfo?
    @State private var approving: Approval?
    @State private var openedRoom: RoomInfo?
    @State private var editing: Editing?
    @State private var settingUp = false
    @State private var makingRoom = false

    /// The Bot card open for editing; `bot` nil makes a new one.
    private struct Editing: Identifiable {
        let id: String
        var bot: BotInfo?
    }
    @Namespace private var zoom

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .fullScreenCover(item: $openedRoom) { room in
                        ChatView(room: room, team: team)
                            .navigationTransition(.zoom(sourceID: "room-" + room.id, in: zoom))
                    }
                if !team.approvals.isEmpty { slip.padding(.top, 22) }
                section("Bot")
                badges
                recent
                if !team.rooms.isEmpty {
                    section("群聊")
                    VStack(spacing: 10) {
                        ForEach(team.rooms) { room in roomRow(room) }
                    }
                    .padding(.horizontal, 20)
                }
            }
            .padding(.bottom, 40)
            // Here, not on the slip: the slip leaves the page when its last approval is answered.
            .fullScreenCover(item: $approving) { approval in
                ApproveView(approval: approval, team: team)
                    .navigationTransition(.zoom(sourceID: "slip", in: zoom))
            }
        }
        .scrollIndicators(.hidden)
        .fullScreenCover(item: $opened) { bot in
            ChatView(bot: bot, team: team)
                .navigationTransition(.zoom(sourceID: bot.id, in: zoom))
        }
        .onAppear {
            Haptics.prepare()
            withAnimation(.spring(response: 0.7, dampingFraction: 0.72).delay(0.15)) { shown = true }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Text("团队")
                    .font(.system(size: 34, weight: .heavy))
                    .tracking(-0.8)
                    .foregroundStyle(Color(hex: 0x0B0B0F))
                Spacer()
                Menu {
                    Button("新建 Bot", systemImage: "plus") { editing = Editing(id: "new") }
                    Button("拉个群", systemImage: "person.3") { makingRoom = true }
                    Button("设置", systemImage: "slider.horizontal.3") { settingUp = true }
                    if team.phase == .demo {
                        Button("退出演示", systemImage: "rectangle.portrait.and.arrow.right") { model.leave() }
                    }
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .accessibilityLabel("设置")
                .sheet(item: $editing) { target in
                    BotEditor(team: team, bot: target.bot)
                }
                .sheet(isPresented: $makingRoom) { RoomEditor(team: team) }
                .fullScreenCover(isPresented: $settingUp) {
                    SettingsView(team: team) { model.leave() }
                }
            }
            HStack(spacing: 8) {
                Circle().fill(chip.color).frame(width: 8, height: 8)
                Text(chip.text)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x1B1B22))
                    .contentTransition(.opacity)
            }
            .padding(.horizontal, 14)
            .frame(height: 34)
            .glassEffect(.regular, in: .capsule)
            .onTapGesture { settingUp = true }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var chip: (text: String, color: Color) {
        switch team.phase {
        case .demo: return ("演示数据，还没接模型", Color(hex: 0x5563E6))
        case .setup: return ("还没接模型，点这里设置", Color(hex: 0xB4232F))
        case .ready:
            let busy = team.doing.count
            if busy > 0 { return ("\(busy) 个在干活", Color(hex: 0x5B8DEF)) }
            guard let found = team.resolve(team.settings.defaultModel) else { return ("还没选模型，点这里设置", Color(hex: 0xB4232F)) }
            return ("\(found.model) · 都在", Color(hex: 0x0C8172))
        }
    }

    // MARK: Approvals

    private var slip: some View {
        let first = team.approvals[0]
        let who = team.bots.first { $0.id == first.botId }?.name ?? "Bot"
        return Button {
            Haptics.grab()
            approving = first
        } label: {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("审 批 单")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(2)
                Spacer()
                Text("\(team.approvals.count) 件")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
            }
            .foregroundStyle(Color(hex: 0x4A4A55))
            Text("\(who)在等你点头")
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(Color(hex: 0x0B0B0F))
            if let reason = first.tool ?? first.reason, !reason.isEmpty {
                Text(reason)
                    .font(.system(size: 15))
                    .foregroundStyle(Color(hex: 0x2A2A33))
                    .lineLimit(2)
            }
            HStack(spacing: 4) {
                Text("点开看看")
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color(hex: 0x1756CC))
        }
        .padding(.init(top: 22, leading: 18, bottom: 16, trailing: 18))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SlipShape().fill(.white))
        .contentShape(Rectangle())
        .matchedTransitionSource(id: "slip", in: zoom)
        }
        .buttonStyle(.plain)
        .shadow(color: Color(hex: 0x141432).opacity(0.14), radius: 18, y: 16)
        .rotationEffect(.degrees(-1.2))
        .padding(.horizontal, 22)
        .scaleEffect(shown ? 1 : 0.92)
        .opacity(shown ? 1 : 0)
    }

    // MARK: Badges

    private func section(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 20, weight: .heavy))
            .foregroundStyle(Color(hex: 0x0B0B0F))
            .padding(.horizontal, 22)
            .padding(.top, 28)
            .padding(.bottom, 4)
    }

    /// Without a model the Bots are asleep.
    private var asleep: Bool { team.phase == .setup }

    @ViewBuilder
    private var badges: some View {
        if team.bots.isEmpty {
            Text("还没有 Bot，点右上角新建一个。")
                .font(.system(size: 15))
                .foregroundStyle(Color(hex: 0x3A3A45))
                .padding(.horizontal, 22)
                .padding(.vertical, 20)
        } else {
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(Array(team.bots.enumerated()), id: \.element.id) { index, bot in
                        let status = team.status(of: bot)
                        let look = BadgeLook(
                            name: bot.name,
                            role: (bot.role?.isEmpty == false ? bot.role : nil) ?? (team.isMain(bot) ? "主 Bot" : "Bot"),
                            status: status.text,
                            light: status.light,
                            tone: BadgeLook.tone(named: bot.color),
                            mood: asleep ? .sleepy : Mood.of(status.text)
                        )
                        let tilt = [-2.0, 1.5, -1.0, 2.0][index % 4]
                        Button {
                            Haptics.grab()
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.5)) { poked = bot.id }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                                withAnimation(.spring(response: 0.5, dampingFraction: 0.45)) { poked = nil }
                                opened = bot
                            }
                        } label: {
                            // The source is the card itself, clipped to its own corners, so nothing shows around it while it zooms.
                            BadgeCard(look: look)
                                .matchedTransitionSource(id: bot.id, in: zoom) { source in
                                    source
                                        .background(.clear)
                                        .clipShape(RoundedRectangle(cornerRadius: BadgeCard.corner, style: .continuous))
                                }
                                .scaleEffect(0.86)
                                .frame(width: 134, height: 180)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("聊天", systemImage: "bubble.left") { opened = bot }
                            Button("改资料", systemImage: "pencil") { editing = Editing(id: bot.id, bot: bot) }
                        }
                        .rotationEffect(.degrees(poked == bot.id ? tilt * 3 : tilt))
                        .scaleEffect(x: poked == bot.id ? 1.07 : 1, y: poked == bot.id ? 0.9 : 1, anchor: .bottom)
                        .offset(y: shown ? (index % 2 == 0 ? 0 : 8) : 60)
                        .opacity(shown ? 1 : 0)
                        .animation(.spring(response: 0.6, dampingFraction: 0.68).delay(0.08 * Double(min(index, 6))), value: shown)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 34)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
    }

    // MARK: Rooms

    /// What each Bot said last, newest first.
    @ViewBuilder
    private var recent: some View {
        let said = team.bots
            .filter { $0.preview?.isEmpty == false }
            .sorted { ($0.lastAt ?? 0) > ($1.lastAt ?? 0) }
            .prefix(5)
        if !said.isEmpty {
            section("最近")
            VStack(spacing: 0) {
                ForEach(Array(said.enumerated()), id: \.element.id) { index, bot in
                    Button {
                        Haptics.grab()
                        opened = bot
                    } label: {
                        HStack(spacing: 12) {
                            Face(tone: BadgeLook.tone(named: bot.color), size: 38, mood: asleep ? .sleepy : Mood.of(team.status(of: bot).text), ears: Ears.of(bot.name))
                                .padding(.top, 8)
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(bot.name)
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(Color(hex: 0x0B0B0F))
                                        .lineLimit(1)
                                    Spacer(minLength: 8)
                                    if let at = bot.lastAt, at > 0 {
                                        Text(Self.ago(at))
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(Color(hex: 0x4A4A55))
                                    }
                                }
                                Text(bot.preview ?? "")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color(hex: 0x3A3A45))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if index < said.count - 1 {
                        Rectangle().fill(Color.black.opacity(0.06)).frame(height: 1).padding(.leading, 64)
                    }
                }
            }
            .glassEffect(.regular, in: .rect(cornerRadius: 24))
            .padding(.horizontal, 20)
        }
    }

    /// How long ago, in a few words.
    private static func ago(_ milliseconds: Double) -> String {
        let seconds = Date().timeIntervalSince1970 - milliseconds / 1000
        if seconds < 60 { return "刚刚" }
        if seconds < 3600 { return "\(Int(seconds / 60)) 分钟前" }
        if seconds < 86400 { return "\(Int(seconds / 3600)) 小时前" }
        if seconds < 86400 * 7 { return "\(Int(seconds / 86400)) 天前" }
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"
        return formatter.string(from: Date(timeIntervalSince1970: milliseconds / 1000))
    }

    private func roomRow(_ room: RoomInfo) -> some View {
        Button {
            Haptics.grab()
            openedRoom = room
        } label: {
        HStack(spacing: 12) {
            ZStack {
                let members: [BotInfo] = (room.members ?? []).compactMap { id in team.bots.first { $0.id == id } }
                Face(tone: BadgeLook.tone(named: members.first?.color), size: 28, ears: Ears.of(members.first?.name ?? ""))
                    .offset(x: -9, y: -4)
                Face(tone: BadgeLook.tone(named: members.count > 1 ? members[1].color : "magenta"), size: 28, ears: Ears.of(members.count > 1 ? members[1].name : "群"))
                    .offset(x: 9, y: 10)
            }
            .frame(width: 46, height: 46)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(room.name)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color(hex: 0x0B0B0F))
                    .lineLimit(1)
                if let preview = room.preview, !preview.isEmpty {
                    Text(preview)
                        .font(.system(size: 14))
                        .foregroundStyle(Color(hex: 0x3A3A45))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .contentShape(.rect(cornerRadius: 24))
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 24))
        .matchedTransitionSource(id: "room-" + room.id, in: zoom) { source in
            source.background(.clear).clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("解散这个群", systemImage: "trash", role: .destructive) { team.deleteRoom(room.id) }
        }
    }
}
