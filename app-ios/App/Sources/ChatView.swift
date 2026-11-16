import PhotosUI
import SwiftUI

struct ChatView: View {
    @ObservedObject var team: TeamModel
    @StateObject private var chat: ChatModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @FocusState private var typing: Bool
    @State private var approving: Approval?
    @State private var picks: [PhotosPickerItem] = []
    @State private var photos: [Data] = []
    @State private var chosen: Set<String> = []
    @State private var unfolded: Set<String> = []
    @State private var viewing: Viewing?
    @State private var pickingPhotos = false
    @State private var takingPhoto = false
    @StateObject private var dictation = Dictation()
    /// What was typed before the user started talking.
    @State private var spokenBase = ""

    /// The photo open full screen.
    private struct Viewing: Identifiable {
        let id: String
        var local: Data?
    }

    init(bot: BotInfo, team: TeamModel) {
        self.team = team
        _chat = StateObject(wrappedValue: ChatModel(bot: bot, team: team))
    }

    init(room: RoomInfo, team: TeamModel) {
        self.team = team
        _chat = StateObject(wrappedValue: ChatModel(room: room, team: team))
    }

    private var isRoom: Bool { chat.roomId != nil }
    private var question: Question? { team.questions[chat.sessionId] }

    /// The Bot as the team knows it now; the one the chat opened with if it is gone.
    private var bot: BotInfo { team.bots.first { $0.id == chat.bot.id } ?? chat.bot }
    private var tone: UInt32 { BadgeLook.tone(named: bot.color) }
    private var working: Bool {
        chat.demoWorking || !chat.streaming.isEmpty || chat.lines.last?.live == true || team.isWorking(chat.key)
    }
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
                        if chat.hasEarlier {
                            Button {
                                Haptics.light()
                                let top = (chat.earlier.first ?? chat.lines.first)?.id
                                Task {
                                    await chat.loadEarlier()
                                    // Stay on the message that was at the top.
                                    if let top { proxy.scrollTo(top, anchor: .top) }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    if chat.loadingEarlier { ProgressView().controlSize(.small) }
                                    Text(chat.loadingEarlier ? "正在取" : "看更早的")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Color(hex: 0x1B1B22))
                                }
                                .padding(.horizontal, 16)
                                .frame(height: 36)
                                .background(Color.white.opacity(0.6), in: .capsule)
                            }
                            .buttonStyle(.plain)
                            .disabled(chat.loadingEarlier)
                        }
                        ForEach(chat.earlier) { line in row(line) }
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
        .onDisappear {
            chat.close()
            if dictation.listening { dictation.stop() }
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
            Face(tone: tone, size: 34, mood: dictation.listening ? .asking : (working ? .busy : .happy), ears: Ears.of(bot.name))
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
        if working { return team.doing[chat.key] ?? "正在干活" }
        if isRoom {
            let count = team.rooms.first { $0.id == chat.roomId }?.members?.count ?? 0
            return count > 0 ? "\(count) 个 Bot 在群里" : "群聊"
        }
        return team.status(of: bot).text
    }

    // MARK: Rows

    @ViewBuilder
    private func row(_ line: ChatLine) -> some View {
        switch line.kind {
        case .user:
            VStack(alignment: .trailing, spacing: 4) {
                if !line.images.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Array(line.images.enumerated()), id: \.offset) { index, data in
                            if let image = UIImage(data: data) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 84, height: 84)
                                    .clipShape(.rect(cornerRadius: 16))
                                    .onTapGesture { viewing = Viewing(id: "\(line.id)-\(index)", local: data) }
                            }
                        }
                    }
                    .opacity(line.local == .sending ? 0.72 : 1)
                } else if !line.refs.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(line.refs.prefix(4), id: \.self) { ref in
                            RemotePhoto(chat: chat, attachmentId: ref)
                                .frame(width: 84, height: 84)
                                .clipShape(.rect(cornerRadius: 16))
                                .onTapGesture { viewing = Viewing(id: ref) }
                        }
                    }
                } else if line.photos > 0 {
                    Text("［图片 ×\(line.photos)］")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(hex: 0x4A4A55))
                }
                if !line.text.isEmpty {
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
                }
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
            VStack(alignment: .leading, spacing: 5) {
                if isRoom, let who = speaker(of: line) {
                    HStack(spacing: 6) {
                        Face(tone: BadgeLook.tone(named: who.color), size: 18, ears: Ears.of(who.name))
                        Text(who.name)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.shade(BadgeLook.tone(named: who.color), amount: 0.5))
                    }
                    .padding(.leading, 6)
                    .padding(.top, 6)
                }
                botText(line)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(BotBubble())
            }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 44)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.9, anchor: .bottomLeading).combined(with: .opacity),
                    removal: .opacity
                ))
        case .steps:
            VStack(alignment: .leading, spacing: 6) {
            Button {
                guard !line.tools.isEmpty else { return }
                Haptics.tick(0.5)
                withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) {
                    if unfolded.contains(line.id) { unfolded.remove(line.id) } else { unfolded.insert(line.id) }
                }
            } label: {
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
                if !line.tools.isEmpty {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color(hex: 0x3A3A45))
                        .rotationEffect(.degrees(unfolded.contains(line.id) ? 90 : 0))
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(Color.white.opacity(0.55), in: .capsule)
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.85), lineWidth: 1))
            }
            .buttonStyle(.plain)
            if unfolded.contains(line.id) {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(line.tools.enumerated()), id: \.offset) { index, tool in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(index + 1)")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color(hex: 0x4A4A55))
                                .frame(width: 20, alignment: .trailing)
                            Text(tool)
                                .font(.system(size: 14))
                                .foregroundStyle(Color(hex: 0x1B1B22))
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.55), in: .rect(cornerRadius: 18))
                .transition(.scale(scale: 0.9, anchor: .topLeading).combined(with: .opacity))
            }
            }
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

    /// Who said a line in a group.
    private func speaker(of line: ChatLine) -> (name: String, color: String?)? {
        if let known = team.bots.first(where: { $0.id == line.speaker }) { return (known.name, known.color) }
        if let name = line.speakerName, !name.isEmpty { return (name, nil) }
        return nil
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
            Text(isRoom ? "在群里说一句，大家会轮流接话。" : "它就住在你的手机里，有什么事直接说。")
                .font(.system(size: 15))
                .foregroundStyle(Color(hex: 0x3A3A45))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 120)
        .padding(.horizontal, 30)
    }

    // MARK: Composer

    private var canSend: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !photos.isEmpty }

    /// Smaller and as JPEG: what the computer takes, and quick to send.
    private static func shrink(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let longest = max(image.size.width, image.size.height)
        let scale = min(1, 1568 / max(1, longest))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let small = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return small.jpegData(compressionQuality: 0.8)
    }

    /// The question the Bot is waiting on: tap an option, or type an answer below.
    private func questionCard(_ asked: Question) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Face(tone: tone, size: 30, mood: .asking, ears: Ears.of(bot.name))
                    .padding(.top, 8)
                VStack(alignment: .leading, spacing: 3) {
                    Text(asked.question ?? "\(bot.name)有个问题")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color(hex: 0x0B0B0F))
                    if let detail = asked.detail, !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 14))
                            .foregroundStyle(Color(hex: 0x3A3A45))
                            .lineLimit(4)
                    }
                }
            }
            let many = asked.multiSelect == true
            ForEach(asked.options ?? [], id: \.label) { option in
                Button {
                    if many {
                        Haptics.tick(0.6)
                        if chosen.contains(option.label) { chosen.remove(option.label) } else { chosen.insert(option.label) }
                    } else {
                        Haptics.grab()
                        chat.answer(asked, selected: [option.label], custom: "")
                    }
                } label: {
                    HStack {
                        Text(option.label)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x0B0B0F))
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        if many {
                            Image(systemName: chosen.contains(option.label) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(Color(hex: 0x1756CC))
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(Color.white.opacity(chosen.contains(option.label) ? 0.95 : 0.7), in: .rect(cornerRadius: 16))
                }
                .buttonStyle(.plain)
            }
            if many && !chosen.isEmpty {
                Button {
                    Haptics.grab()
                    chat.answer(asked, selected: (asked.options ?? []).map(\.label).filter(chosen.contains), custom: "")
                    chosen = []
                } label: {
                    Text("选好了")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(Color(hex: 0x1756CC), in: .capsule)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
    private var showStop: Bool { working && !canSend }

    /// What the round button does now.
    private enum Act { case hush, stop, send, talk }

    private var act: Act {
        if dictation.listening { return .hush }
        if showStop { return .stop }
        if canSend { return .send }
        return .talk
    }

    private var action: some View {
        let act = self.act
        let icon: String = switch act {
        case .hush: "waveform"
        case .stop: "stop.fill"
        case .send: "arrow.up"
        case .talk: "mic.fill"
        }
        let fill: AnyShapeStyle = switch act {
        case .hush: AnyShapeStyle(Color(hex: 0xF0616D))
        case .stop: AnyShapeStyle(Color(hex: 0x0B0B0F))
        case .send: AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x2A6FE6), Color(hex: 0x1756CC)], startPoint: .top, endPoint: .bottom))
        case .talk: AnyShapeStyle(Color.black.opacity(0.06))
        }
        let spoken: String = switch act {
        case .hush: "说完了"
        case .stop: "让它停下"
        case .send: "发送"
        case .talk: "说话"
        }
        return Button {
            switch act {
            case .hush:
                Haptics.light()
                dictation.stop()
            case .stop:
                Haptics.lock()
                chat.stop()
            case .send:
                Haptics.grab()
                if let asked = question {
                    chat.answer(asked, selected: [], custom: draft)
                } else {
                    chat.send(draft, photos: photos)
                    photos = []
                }
                draft = ""
            case .talk:
                Haptics.grab()
                typing = false
                spokenBase = draft
                dictation.onText = { heard in
                    draft = spokenBase.isEmpty ? heard : spokenBase + heard
                }
                Task { await dictation.start() }
            }
        } label: {
            ZStack {
                if act == .hush {
                    Circle()
                        .fill(Color(hex: 0xF0616D).opacity(0.28))
                        .scaleEffect(1 + dictation.level * 0.7)
                        .animation(.easeOut(duration: 0.12), value: dictation.level)
                }
                Image(systemName: icon)
                    .font(.system(size: act == .stop ? 14 : 17, weight: .heavy))
                    .foregroundStyle(act == .talk ? Color(hex: 0x0B0B0F) : .white)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.variableColor.iterative, isActive: act == .hush)
                    .frame(width: 44, height: 44)
                    .background(fill, in: .circle)
            }
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: act)
        .accessibilityLabel(spoken)
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if let waiting = team.approvals.first(where: { $0.chat == chat.key || (!isRoom && $0.chat == nil && $0.botId == chat.bot.id) }) {
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
            if let asked = question {
                questionCard(asked)
            }
            if !photos.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(Array(photos.enumerated()), id: \.offset) { index, data in
                            if let image = UIImage(data: data) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 64, height: 64)
                                    .clipShape(.rect(cornerRadius: 14))
                                    .overlay(alignment: .topTrailing) {
                                        Button {
                                            Haptics.light()
                                            withAnimation(.smooth) { _ = photos.remove(at: index) }
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 20))
                                                .foregroundStyle(.white, Color.black.opacity(0.55))
                                        }
                                        .buttonStyle(.plain)
                                        .offset(x: 6, y: -6)
                                        .accessibilityLabel("去掉这张")
                                    }
                            }
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.top, 8)
                }
                .scrollIndicators(.hidden)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if let problem = dictation.problem {
                Text(problem)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: 0xB4232F))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.8), in: .capsule)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onTapGesture { withAnimation(.smooth) { dictation.problem = nil } }
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
                if question == nil {
                    Menu {
                        Button("拍一张", systemImage: "camera") { takingPhoto = true }
                        Button("从相册选", systemImage: "photo.on.rectangle") { pickingPhotos = true }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Color(hex: 0x0B0B0F))
                            .frame(width: 44, height: 44)
                            .background(Color.black.opacity(0.06), in: .circle)
                    }
                    .accessibilityLabel("添加照片")
                }
                TextField(dictation.listening ? "正在听，说完点右边" : (question == nil ? "给\(bot.name)发消息" : "也可以写下你的回答"), text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .font(.system(size: 17))
                    .foregroundStyle(Color(hex: 0x0B0B0F))
                    .focused($typing)
                    .padding(.leading, question == nil ? 4 : 14)
                    .padding(.vertical, 11)
                action
            }
            .padding(6)
            .glassEffect(.regular, in: .rect(cornerRadius: 28))
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .animation(.smooth, value: chat.error)
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: question)
        .animation(.smooth, value: photos.count)
        .photosPicker(isPresented: $pickingPhotos, selection: $picks, maxSelectionCount: 4, matching: .images)
        .fullScreenCover(isPresented: $takingPhoto) {
            CameraPicker { data in
                if let data, let small = Self.shrink(data), photos.count < 4 { photos.append(small) }
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(item: $viewing) { shown in
            PhotoViewer(chat: chat, attachmentId: shown.local == nil ? shown.id : nil, local: shown.local)
        }
        .onChange(of: picks) {
            guard !picks.isEmpty else { return }
            let picked = picks
            picks = []
            Task {
                for item in picked {
                    if let data = try? await item.loadTransferable(type: Data.self), let small = Self.shrink(data), photos.count < 4 {
                        photos.append(small)
                    }
                }
            }
        }
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
