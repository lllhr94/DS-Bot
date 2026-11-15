import SwiftUI

struct HomeView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var team: TeamModel

    @State private var shown = false
    @State private var poked: String?
    @State private var opened: BotInfo?
    @Namespace private var zoom

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                if !team.approvals.isEmpty { slip.padding(.top, 22) }
                section("Bot")
                badges
                if !team.rooms.isEmpty {
                    section("群聊")
                    VStack(spacing: 10) {
                        ForEach(team.rooms) { room in roomRow(room) }
                    }
                    .padding(.horizontal, 20)
                }
            }
            .padding(.bottom, 40)
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
                    if team.phase == .demo {
                        Button("退出演示", systemImage: "rectangle.portrait.and.arrow.right") { model.leave() }
                    } else {
                        Button("断开这台电脑", systemImage: "link.badge.plus", role: .destructive) { model.leave() }
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
            if team.phase == .unpaired {
                Button {
                    Haptics.light()
                    model.leave()
                } label: {
                    Text("重新配对")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(height: 30)
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .tint(Color(hex: 0x1F6AE8))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var chip: (text: String, color: Color) {
        switch team.phase {
        case .connecting: return ("正在连接 \(team.hostName)", Color(hex: 0xD9930D))
        case .online: return (team.hostName.isEmpty ? "已连接" : "已连接 \(team.hostName)", Color(hex: 0x0C8172))
        case .offline(let why): return (why, Color(hex: 0xB4232F))
        case .unpaired: return ("电脑已经不认识这台手机了", Color(hex: 0xB4232F))
        case .demo: return ("演示数据，还没连接电脑", Color(hex: 0x5563E6))
        }
    }

    // MARK: Approvals

    private var slip: some View {
        let first = team.approvals[0]
        let who = team.bots.first { $0.id == first.botId }?.name ?? "Bot"
        return VStack(alignment: .leading, spacing: 10) {
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
            if let reason = first.reason ?? first.tool, !reason.isEmpty {
                Text(reason)
                    .font(.system(size: 15))
                    .foregroundStyle(Color(hex: 0x2A2A33))
                    .lineLimit(2)
            }
            Text("在手机上批准，下一版接上。")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(hex: 0x4A4A55))
        }
        .padding(.init(top: 22, leading: 18, bottom: 16, trailing: 18))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SlipShape().fill(.white))
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

    @ViewBuilder
    private var badges: some View {
        if team.bots.isEmpty {
            Text(team.phase == .online ? "这台电脑上还没有 Bot。" : "连上电脑后，Bot 会出现在这里。")
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
                            tone: BadgeLook.tone(named: bot.color)
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
                            BadgeCard(look: look)
                                .scaleEffect(0.86)
                                .frame(width: 134, height: 180)
                                .matchedTransitionSource(id: bot.id, in: zoom)
                        }
                        .buttonStyle(.plain)
                        .rotationEffect(.degrees(poked == bot.id ? tilt * 3 : tilt))
                        .scaleEffect(poked == bot.id ? 0.94 : 1)
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

    private func roomRow(_ room: RoomInfo) -> some View {
        HStack(spacing: 12) {
            ZStack {
                let members: [BotInfo] = (room.members ?? []).compactMap { id in team.bots.first { $0.id == id } }
                Circle()
                    .fill(Color.shade(BadgeLook.tone(named: members.first?.color), amount: 0.84))
                    .frame(width: 30, height: 30)
                    .offset(x: -8, y: -8)
                Circle()
                    .fill(Color.shade(BadgeLook.tone(named: members.count > 1 ? members[1].color : "magenta"), amount: 0.84))
                    .frame(width: 30, height: 30)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    .offset(x: 8, y: 8)
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
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }
}
