import SwiftUI

/// Model services, the default model, and what the Bots remember about the user.
struct SettingsView: View {
    @ObservedObject var team: TeamModel
    var onLeaveDemo: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var adding = false
    @State private var removing: Endpoint?

    var body: some View {
        ZStack {
            Aurora(seed: 6.3).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("设置")
                            .font(.system(size: 34, weight: .heavy))
                            .tracking(-0.8)
                        Spacer()
                        Button {
                            Haptics.light()
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 17, weight: .semibold))
                                .frame(width: 26, height: 26)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .controlSize(.large)
                        .accessibilityLabel("关闭")
                    }
                    .padding(.top, 10)

                    if team.phase == .demo {
                        card {
                            Text("现在是演示数据。接上自己的模型后，Bot 才会真的回答。")
                                .font(.system(size: 15))
                            Button("退出演示，去接模型") {
                                dismiss()
                                onLeaveDemo()
                            }
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color(hex: 0x1756CC))
                        }
                        .padding(.top, 18)
                    } else {
                        section("模型服务")
                        card {
                            ForEach(team.settings.endpoints) { endpoint in
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(endpoint.name).font(.system(size: 16, weight: .bold))
                                        Text("\(URL(string: endpoint.baseURL)?.host ?? endpoint.baseURL) · \(endpoint.models.count) 个模型")
                                            .font(.system(size: 13))
                                            .foregroundStyle(Color(hex: 0x3A3A45))
                                    }
                                    Spacer()
                                    Button {
                                        removing = endpoint
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(Color(hex: 0xB4232F))
                                            .frame(width: 36, height: 36)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("删掉 \(endpoint.name)")
                                }
                                Divider().opacity(0.5)
                            }
                            Button {
                                Haptics.light()
                                adding = true
                            } label: {
                                Label("添加服务", systemImage: "plus")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Color(hex: 0x1756CC))
                            }
                            .buttonStyle(.plain)
                        }

                        if !team.models.isEmpty {
                            section("默认模型")
                            card {
                                Menu {
                                    ForEach(team.models) { item in
                                        Button {
                                            Haptics.tick(0.6)
                                            team.setDefaultModel(item.ref)
                                        } label: {
                                            if team.settings.defaultModel == item.ref {
                                                Label("\(item.name ?? item.ref) · \(item.providerName ?? "")", systemImage: "checkmark")
                                            } else {
                                                Text("\(item.name ?? item.ref) · \(item.providerName ?? "")")
                                            }
                                        }
                                    }
                                } label: {
                                    HStack {
                                        Text(team.modelTitle(team.settings.defaultModel))
                                            .font(.system(size: 16, weight: .semibold))
                                            .lineLimit(1)
                                        Spacer()
                                        Image(systemName: "chevron.up.chevron.down")
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundStyle(Color(hex: 0x4A4A55))
                                    }
                                }
                                .buttonStyle(.plain)
                                Text("没单独选模型的 Bot 都用它。DeepSeek 看不了图，发图片给 Bot 时最好用 Claude 或别的能看图的模型。")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color(hex: 0x4A4A55))
                            }
                        }

                        section("它们记得你的事")
                        card {
                            if team.memories.isEmpty {
                                Text("还没有。聊天时说起你自己的事，Bot 会记下来，以后每次聊天都记得。")
                                    .font(.system(size: 15))
                                    .foregroundStyle(Color(hex: 0x3A3A45))
                            }
                            ForEach(team.memories) { memory in
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Text(memory.text)
                                        .font(.system(size: 15))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Button {
                                        Haptics.light()
                                        withAnimation(.smooth) { team.deleteMemory(memory.id) }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 18))
                                            .foregroundStyle(Color(hex: 0x9A9AA6))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("忘掉这条")
                                }
                                .transition(.opacity)
                            }
                        }
                    }

                    Text("Bot 团队 \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(hex: 0x6A6A75))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 30)
                }
                .foregroundStyle(Color(hex: 0x0B0B0F))
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .preferredColorScheme(.light)
        .fontDesign(.rounded)
        .sheet(isPresented: $adding) {
            SetupView(team: team) { adding = false }
        }
        .confirmationDialog("删掉 \(removing?.name ?? "")？用它的 Bot 会改用默认模型。", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            Button("删掉", role: .destructive) {
                if let removing { withAnimation(.smooth) { team.removeEndpoint(removing.id) } }
                removing = nil
            }
            Button("先留着", role: .cancel) { removing = nil }
        }
    }

    private func section(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 20, weight: .heavy))
            .padding(.horizontal, 4)
            .padding(.top, 26)
            .padding(.bottom, 10)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) { content() }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }
}

/// Makes a group: a name and who is in it.
struct RoomEditor: View {
    @ObservedObject var team: TeamModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var members: Set<String> = []

    private var canSave: Bool { members.count >= 2 }

    var body: some View {
        ZStack {
            Aurora(seed: 8.1).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Button {
                            Haptics.light()
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 17, weight: .semibold))
                                .frame(width: 26, height: 26)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .controlSize(.large)
                        .accessibilityLabel("关闭")
                        Spacer()
                    }
                    Text("拉个群")
                        .font(.system(size: 30, weight: .heavy))
                    Text("你说一句，群里的 Bot 按顺序接话。")
                        .font(.system(size: 16))
                        .foregroundStyle(Color(hex: 0x2A2A33))
                    TextField("群名，比如：周末去哪玩", text: $name)
                        .font(.system(size: 18, weight: .semibold))
                        .padding(.horizontal, 16)
                        .frame(height: 52)
                        .glassEffect(.regular, in: .rect(cornerRadius: 18))
                    Text("选至少两个 Bot")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(hex: 0x4A4A55))
                        .padding(.leading, 6)
                        .padding(.top, 6)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 14) {
                        ForEach(team.bots) { bot in
                            let picked = members.contains(bot.id)
                            Button {
                                Haptics.tick(0.6)
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) {
                                    if picked { members.remove(bot.id) } else { members.insert(bot.id) }
                                }
                            } label: {
                                VStack(spacing: 6) {
                                    Face(tone: BadgeLook.tone(named: bot.color), size: 56, mood: picked ? .happy : .sleepy, ears: Ears.of(bot.name))
                                        .padding(.top, 10)
                                    Text(bot.name)
                                        .font(.system(size: 14, weight: .bold))
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.white.opacity(picked ? 0.85 : 0.4), in: .rect(cornerRadius: 22))
                                .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(picked ? Color(hex: 0x1756CC).opacity(0.5) : .clear, lineWidth: 2))
                                .scaleEffect(picked ? 1.04 : 1)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Button {
                        let picked = team.bots.map(\.id).filter(members.contains)
                        let given = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        let names = picked.compactMap { id in team.bots.first { $0.id == id }?.name }
                        team.createRoom(name: given.isEmpty ? names.joined(separator: "、") : given, members: picked)
                        Haptics.thud()
                        dismiss()
                    } label: {
                        Text("建群")
                            .font(.system(size: 18, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .disabled(!canSave)
                    .padding(.top, 8)
                }
                .foregroundStyle(Color(hex: 0x0B0B0F))
                .padding(.horizontal, 22)
                .padding(.top, 10)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .preferredColorScheme(.light)
        .fontDesign(.rounded)
    }
}
