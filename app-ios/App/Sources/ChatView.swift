import SwiftUI

struct ChatView: View {
    @ObservedObject var team: TeamModel
    @StateObject private var chat: ChatModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @FocusState private var typing: Bool
    @State private var approving: Approval?

    init(bot: BotInfo, team: TeamModel) {
        self.team = team
        _chat = StateObject(wrappedValue: ChatModel(bot: bot, team: team))
    }

    /// The Bot as the team knows it now; the one the chat opened with if it is gone.
    private var bot: BotInfo { team.bots.first { $0.id == chat.bot.id } ?? chat.bot }
    private var tone: UInt32 { BadgeLook.tone(named: bot.color) }
    private var working: Bool { chat.demoWorking || team.work.bots?[bot.id] != nil || !chat.streaming.isEmpty }
    /// Changes whenever the chat grows, so the view can follow the newest row.
    private var rows: Int { chat.lines.count &+ chat.pending.count &* 1000 }
    private var flow: Int { chat.streaming.count &+ (chat.fresh?.shown ?? 0) }

    var body: some View {
        ZStack {
            Aurora(seed: 3.1).ignoresSafeArea()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if chat.loaded && chat.lines.isEmpty && chat.pending.isEmpty && chat.streaming.isEmpty {
                            empty
                        }
                        ForEach(chat.lines) { line in row(line) }
                        ForEach(chat.pending) { line in row(line) }
                        if !chat.streaming.isEmpty {
                            MessageText(text: chat.streaming, tail: 1)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(BotBubble())
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.trailing, 44)
                        } else if working && chat.lines.last?.live != true {
                            ThinkingDots(color: Color.shade(tone, amount: 0.84))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .transition(.scale(scale: 0.6, anchor: .leading).combined(with: .opacity))
                        }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 6)
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: working)
                }
                .defaultScrollAnchor(.bottom)
                .scrollDismissesKeyboard(.interactively)
                .scrollIndicators(.hidden)
                .onChange(of: rows) {
                    withAnimation(.smooth(duration: 0.25)) { proxy.scrollTo("end", anchor: .bottom) }
                }
                // While a reply flows the view just stays on its last line; animating every frame would stutter.
                .onChange(of: flow) { proxy.scrollTo("end", anchor: .bottom) }
                .onChange(of: typing) {
                    guard typing else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        withAnimation(.smooth(duration: 0.25)) { proxy.scrollTo("end", anchor: .bottom) }
                    }
                }
            }
            if !chat.loaded {
                ProgressView().controlSize(.large)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        .preferredColorScheme(.light)
        .fontDesign(.rounded)
        .onAppear {
            Haptics.prepare()
            chat.open()
        }
        .onDisappear { chat.close() }
        .onChange(of: team.phase) {
            if team.phase == .online { Task { await chat.refresh() } }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                Haptics.light()
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x0B0B0F))
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("返回")
            Face(tone: tone, size: 34, mood: working ? .busy : .happy, ears: Ears.of(bot.name))
                .padding(.top, 8)
                .padding(.horizontal, 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(bot.name)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color(hex: 0x0B0B0F))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(hex: 0x3A3A45))
                    .lineLimit(1)
                    .contentTransition(.opacity)
                    .animation(.smooth, value: subtitle)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(height: 60)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, 14)
        .padding(.top, 4)
        .padding(.bottom, 6)
    }

    private var subtitle: String {
        switch team.phase {
        case .offline, .connecting: return "正在连接电脑"
        case .unpaired: return "需要重新配对"
        default: return working ? "正在干活" : team.status(of: bot).text
        }
    }

    // MARK: Rows

    @ViewBuilder
    private func row(_ line: ChatLine) -> some View {
        switch line.kind {
        case .user:
            VStack(alignment: .trailing, spacing: 4) {
                Text(line.text)
                    .font(.system(size: 17))
                    .lineSpacing(3)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(
                        LinearGradient(colors: [Color(hex: 0x2A6FE6), Color(hex: 0x1756CC)], startPoint: .top, endPoint: .bottom),
                        in: .rect(topLeadingRadius: 22, bottomLeadingRadius: 22, bottomTrailingRadius: 6, topTrailingRadius: 22)
                    )
                    .shadow(color: Color(hex: 0x1756CC).opacity(0.26), radius: 9, y: 8)
                    .opacity(line.local == .sending ? 0.72 : 1)
                    .textSelection(.enabled)
                if line.local == .failed {
                    HStack(spacing: 12) {
                        Button("重发") { Haptics.light(); chat.retry(line.id) }
                        Button("删掉") { chat.discard(line.id) }
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: 0xB4232F))
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, 56)
            .transition(.asymmetric(
                insertion: .scale(scale: 0.82, anchor: .bottomTrailing).combined(with: .opacity).combined(with: .offset(y: 24)),
                removal: .opacity
            ))
        case .bot:
            botText(line)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(BotBubble())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 44)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.9, anchor: .bottomLeading).combined(with: .opacity),
                    removal: .opacity
                ))
        case .steps:
            HStack(spacing: 8) {
                if line.live {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Color(hex: 0x0C8172))
                }
                Text(line.text)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x1B1B22))
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(Color.white.opacity(0.55), in: .capsule)
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.85), lineWidth: 1))
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.opacity)
        case .note:
            Text(line.text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(hex: 0x4A4A55))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2)
                .transition(.opacity)
        }
    }

    /// The reply that just finished keeps flowing out where the streaming row stopped, then its tail clears.
    @ViewBuilder
    private func botText(_ line: ChatLine) -> some View {
        if let fresh = chat.fresh, fresh.id == line.id {
            MessageText(text: fresh.shown.map { String(line.text.prefix($0)) } ?? line.text, tail: fresh.shown == nil ? 0 : 1)
        } else {
            MessageText(text: line.text).equatable()
        }
    }

    private var empty: some View {
        VStack(spacing: 14) {
            Face(tone: tone, size: 96, ears: Ears.of(bot.name))
            Text("跟\(bot.name)说点什么吧")
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(Color(hex: 0x0B0B0F))
            Text("它在你的电脑上干活，做完会在这里告诉你。")
                .font(.system(size: 15))
                .foregroundStyle(Color(hex: 0x3A3A45))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 120)
        .padding(.horizontal, 30)
    }

    // MARK: Composer

    private var canSend: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var showStop: Bool { working && !canSend }

    private var composer: some View {
        VStack(spacing: 8) {
            if let waiting = team.approvals.first(where: { $0.botId == chat.bot.id }) {
                Button {
                    Haptics.grab()
                    typing = false
                    approving = waiting
                } label: {
                    HStack(spacing: 10) {
                        Text("审 批 单")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(1.5)
                            .foregroundStyle(Color(hex: 0x4A4A55))
                        Text(waiting.tool ?? waiting.reason ?? "等你点头")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x0B0B0F))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color(hex: 0x1756CC))
                    }
                    .padding(.init(top: 16, leading: 16, bottom: 12, trailing: 14))
                    .background(SlipShape().fill(.white))
                    .shadow(color: Color(hex: 0x141432).opacity(0.14), radius: 12, y: 8)
                    .rotationEffect(.degrees(-0.8))
                    .padding(.horizontal, 6)
                }
                .buttonStyle(.plain)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityLabel("\(bot.name)在等你批准")
            }
            if let error = chat.error {
                Text(error)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: 0xB4232F))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.8), in: .capsule)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onTapGesture { withAnimation(.smooth) { chat.error = nil } }
            }
            HStack(alignment: .bottom, spacing: 6) {
                TextField("给\(bot.name)发消息", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .font(.system(size: 17))
                    .foregroundStyle(Color(hex: 0x0B0B0F))
                    .focused($typing)
                    .padding(.leading, 14)
                    .padding(.vertical, 11)
                Button {
                    if showStop {
                        Haptics.lock()
                        chat.stop()
                    } else {
                        Haptics.grab()
                        chat.send(draft)
                        draft = ""
                    }
                } label: {
                    Image(systemName: showStop ? "stop.fill" : "arrow.up")
                        .font(.system(size: showStop ? 14 : 17, weight: .heavy))
                        .foregroundStyle(.white)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 44, height: 44)
                        .background(
                            showStop
                                ? AnyShapeStyle(Color(hex: 0x0B0B0F))
                                : AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x2A6FE6), Color(hex: 0x1756CC)], startPoint: .top, endPoint: .bottom)),
                            in: .circle
                        )
                        .opacity(canSend || showStop ? 1 : 0.35)
                        .scaleEffect(canSend || showStop ? 1 : 0.9)
                }
                .buttonStyle(.plain)
                .disabled(!canSend && !showStop)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: canSend)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: showStop)
                .accessibilityLabel(showStop ? "让它停下" : "发送")
            }
            .padding(6)
            .glassEffect(.regular, in: .rect(cornerRadius: 28))
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .animation(.smooth, value: chat.error)
        .animation(.spring(response: 0.45, dampingFraction: 0.75), value: team.approvals)
        .fullScreenCover(item: $approving) { approval in
            ApproveView(approval: approval, team: team)
        }
    }
}

/// The frosted white bubble of a Bot's message.
private struct BotBubble: View {
    var body: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 22, bottomLeadingRadius: 6, bottomTrailingRadius: 22, topTrailingRadius: 22)
        shape
            .fill(Color.white.opacity(0.78))
            .overlay(shape.strokeBorder(Color.white.opacity(0.9), lineWidth: 1))
            .shadow(color: Color(hex: 0x141432).opacity(0.08), radius: 11, y: 8)
    }
}

/// A Bot's message: plain paragraphs with inline Markdown, and code in its own boxes.
struct MessageText: View, Equatable {
    let text: String
    /// Above 0 while the text is still arriving: how strongly its newest characters fade in.
    var tail: Double?

    private enum Block { case prose(AttributedString), code(String) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            let parts = blocks
            ForEach(Array(parts.enumerated()), id: \.offset) { index, block in
                switch block {
                case .prose(let prose):
                    if let tail {
                        Text(prose)
                            .font(.system(size: 17))
                            .lineSpacing(4)
                            .foregroundStyle(Color(hex: 0x0B0B0F))
                            .tint(Color(hex: 0x1756CC))
                            .textRenderer(TailRenderer(strength: index == parts.count - 1 ? tail : 0))
                    } else {
                        Text(prose)
                            .font(.system(size: 17))
                            .lineSpacing(4)
                            .foregroundStyle(Color(hex: 0x0B0B0F))
                            .tint(Color(hex: 0x1756CC))
                            .textSelection(.enabled)
                    }
                case .code(let code):
                    ScrollView(.horizontal) {
                        Text(code)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(Color(hex: 0x1B1B22))
                            .padding(10)
                            .textSelection(.enabled)
                    }
                    .scrollIndicators(.hidden)
                    .background(Color(hex: 0xF1F0F6), in: .rect(cornerRadius: 10))
                }
            }
        }
    }

    private var blocks: [Block] {
        var out: [Block] = []
        // Odd pieces between ``` fences are code.
        for (index, piece) in text.components(separatedBy: "```").enumerated() {
            if index % 2 == 1 {
                var lines = piece.components(separatedBy: "\n")
                // The first line of a fence names the language.
                if lines.count > 1 { lines.removeFirst() }
                let code = lines.joined(separator: "\n").trimmingCharacters(in: .newlines)
                if !code.isEmpty { out.append(.code(code)) }
            } else {
                let prose = piece.trimmingCharacters(in: .whitespacesAndNewlines)
                if !prose.isEmpty { out.append(.prose(Self.inline(prose))) }
            }
        }
        return out
    }

    /// Inline Markdown, with headings made bold and list dashes made bullets.
    private static func inline(_ prose: String) -> AttributedString {
        let lines = prose.components(separatedBy: "\n").map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") {
                let title = trimmed.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
                return title.isEmpty ? "" : "**\(title.replacingOccurrences(of: "**", with: ""))**"
            }
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                let indent = String(line.prefix { $0 == " " })
                return "\(indent)•  \(trimmed.dropFirst(2))"
            }
            return line
        }
        let source = lines.joined(separator: "\n")
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        return (try? AttributedString(markdown: source, options: options)) ?? AttributedString(source)
    }
}

/// Fades the newest glyphs in: the last one is the faintest. `strength` 0 draws the text as it is.
private struct TailRenderer: TextRenderer {
    var strength: Double
    var tail = 10

    var animatableData: Double {
        get { strength }
        set { strength = newValue }
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        var slices: [Text.Layout.RunSlice] = []
        for line in layout {
            for run in line {
                for slice in run { slices.append(slice) }
            }
        }
        let total = slices.count
        for (index, slice) in slices.enumerated() {
            let fromEnd = total - 1 - index
            if fromEnd >= tail || strength <= 0 {
                context.draw(slice)
                continue
            }
            let depth = 1 - Double(fromEnd) / Double(tail)
            var soft = context
            soft.opacity = 1 - depth * 0.9 * strength
            soft.draw(slice)
        }
    }
}

/// Three dots that breathe while the Bot has not started writing yet.
private struct ThinkingDots: View {
    let color: Color
    @State private var on = false

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(color)
                    .frame(width: 9, height: 9)
                    .scaleEffect(on ? 1 : 0.55)
                    .opacity(on ? 1 : 0.4)
                    .animation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true).delay(Double(index) * 0.16), value: on)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(BotBubble())
        .onAppear { on = true }
        .accessibilityLabel("正在想")
    }
}
