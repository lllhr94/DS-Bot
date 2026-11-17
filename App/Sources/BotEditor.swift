import SwiftUI

/// A Bot's card to fill in: its name, what it does, and its color. Makes a new Bot when `bot` is nil.
struct BotEditor: View {
    @ObservedObject var team: TeamModel
    let bot: BotInfo?
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var role: String
    @State private var color: String
    @State private var model: String?
    @State private var instructions: String
    @State private var busy = false
    @State private var error: String?
    @State private var confirmingDelete = false
    @FocusState private var naming: Bool

    private static let palette = ["blue", "violet", "magenta", "red", "orange", "yellow", "green", "aurora", "cyan", "brown", "gray", "black"]

    init(team: TeamModel, bot: BotInfo?) {
        self.team = team
        self.bot = bot
        _name = State(initialValue: bot?.name ?? "")
        _role = State(initialValue: bot?.role ?? "")
        _color = State(initialValue: bot?.color.flatMap { BadgeLook.tones[$0] == nil ? nil : $0 } ?? "blue")
        _instructions = State(initialValue: bot?.instructions ?? "")
    }

    private var tone: UInt32 { BadgeLook.tone(named: color) }
    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { !trimmed.isEmpty && !busy }

    var body: some View {
        ZStack {
            Aurora(seed: 7.4).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
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

                    BadgeCard(look: BadgeLook(
                        name: trimmed.isEmpty ? "新 Bot" : trimmed,
                        role: role.isEmpty ? "它负责什么" : role,
                        status: bot == nil ? "马上到岗" : "在岗",
                        light: Color(hex: 0x34C98A),
                        tone: tone
                    ))
                    .rotationEffect(.degrees(-3))
                    .animation(.spring(response: 0.4, dampingFraction: 0.6), value: color)
                    .padding(.vertical, 6)

                    VStack(alignment: .leading, spacing: 8) {
                        label("名字")
                        TextField("比如：小助手", text: $name)
                            .font(.system(size: 18, weight: .semibold))
                            .focused($naming)
                            .submitLabel(.done)
                            .padding(.horizontal, 16)
                            .frame(height: 52)
                            .glassEffect(.regular, in: .rect(cornerRadius: 18))
                        label("它负责什么").padding(.top, 6)
                        TextField("比如：查资料 · 写总结", text: $role)
                            .font(.system(size: 17))
                            .submitLabel(.done)
                            .padding(.horizontal, 16)
                            .frame(height: 52)
                            .glassEffect(.regular, in: .rect(cornerRadius: 18))
                        label("性格和说明").padding(.top, 6)
                        TextField("比如：说话温柔，爱用表情；擅长做饭，会根据冰箱里有的东西出主意。", text: $instructions, axis: .vertical)
                            .font(.system(size: 16))
                            .lineLimit(3...8)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .glassEffect(.regular, in: .rect(cornerRadius: 18))
                        if !team.models.isEmpty {
                            label("用哪个模型").padding(.top, 6)
                            Menu {
                                Button {
                                    model = ""
                                } label: {
                                    if (model ?? bot?.model ?? "").isEmpty {
                                        Label("跟默认的走", systemImage: "checkmark")
                                    } else {
                                        Text("跟默认的走")
                                    }
                                }
                                ForEach(team.models) { item in
                                    Button {
                                        model = item.ref
                                    } label: {
                                        if (model ?? bot?.model) == item.ref {
                                            Label(Self.title(item), systemImage: "checkmark")
                                        } else {
                                            Text(Self.title(item))
                                        }
                                    }
                                }
                            } label: {
                                HStack {
                                    Text(team.models.first { $0.ref == (model ?? bot?.model) }.map(Self.title) ?? "跟默认的走（\(team.modelTitle(team.settings.defaultModel))）")
                                        .font(.system(size: 17))
                                        .lineLimit(1)
                                    Spacer()
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(Color(hex: 0x4A4A55))
                                }
                                .padding(.horizontal, 16)
                                .frame(height: 52)
                                .glassEffect(.regular, in: .rect(cornerRadius: 18))
                            }
                            .buttonStyle(.plain)
                        }
                        label("颜色").padding(.top, 6)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 12) {
                            ForEach(Self.palette, id: \.self) { item in
                                Button {
                                    Haptics.tick(0.6)
                                    color = item
                                } label: {
                                    Circle()
                                        .fill(Color.shade(BadgeLook.tone(named: item), lift: 0.36))
                                        .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                                        .overlay {
                                            if color == item {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 15, weight: .black))
                                                    .foregroundStyle(.white)
                                            }
                                        }
                                        .frame(width: 44, height: 44)
                                        .scaleEffect(color == item ? 1.12 : 1)
                                        .shadow(color: Color.shade(BadgeLook.tone(named: item), amount: 0.6).opacity(0.25), radius: 6, y: 4)
                                        .animation(.spring(response: 0.3, dampingFraction: 0.55), value: color)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(item)
                            }
                        }
                    }
                    .foregroundStyle(Color(hex: 0x0B0B0F))

                    if let error {
                        Text(error)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color(hex: 0xB4232F))
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        save()
                    } label: {
                        HStack(spacing: 8) {
                            if busy { ProgressView().tint(.white) }
                            Text(bot == nil ? "让它入职" : "保存")
                                .font(.system(size: 18, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .disabled(!canSave)
                    .padding(.top, 4)

                    if let bot, !team.isMain(bot) {
                        Button("让它离职") { confirmingDelete = true }
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color(hex: 0xB4232F))
                            .buttonStyle(.plain)
                            .frame(height: 44)
                            .disabled(busy)
                            .confirmationDialog("让\(bot.name)离职？它和你的对话会一起删掉，不能恢复。", isPresented: $confirmingDelete, titleVisibility: .visible) {
                                Button("删除这个 Bot", role: .destructive) { remove(bot) }
                                Button("先留着", role: .cancel) {}
                            }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 10)
                .padding(.bottom, 30)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)
        }
        .preferredColorScheme(.light)
        .fontDesign(.rounded)
        .onAppear { if bot == nil { naming = true } }
    }

    private static func title(_ model: ModelInfo) -> String {
        let name = model.name?.isEmpty == false ? model.name! : model.ref
        if let provider = model.providerName, !provider.isEmpty { return "\(name) · \(provider)" }
        return name
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(Color(hex: 0x4A4A55))
            .padding(.leading, 6)
    }

    private func save() {
        guard canSave else { return }
        busy = true
        error = nil
        Task {
            do {
                try await team.saveBot(id: bot?.id, name: trimmed, role: role.trimmingCharacters(in: .whitespacesAndNewlines), color: color, model: model,
                                       instructions: instructions.trimmingCharacters(in: .whitespacesAndNewlines))
                Haptics.thud()
                dismiss()
            } catch {
                busy = false
                Haptics.lock()
                self.error = "没存上：\(error.localizedDescription)"
            }
        }
    }

    private func remove(_ bot: BotInfo) {
        busy = true
        error = nil
        Task {
            do {
                try await team.deleteBot(bot.id)
                Haptics.lock()
                dismiss()
            } catch {
                busy = false
                self.error = "没删掉：\(error.localizedDescription)"
            }
        }
    }
}
