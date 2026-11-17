import SwiftUI

/// One approval slip at a time: slide to stamp it approved, or turn it down.
struct ApproveView: View {
    @ObservedObject var team: TeamModel
    @Environment(\.dismiss) private var dismiss

    private enum Verdict { case allowed, rejected }

    /// Kept here: the computer drops the approval the moment it is answered, the slip stays to be stamped.
    @State private var current: Approval
    @State private var verdict: Verdict?
    @State private var stampedAt = Date()
    @State private var busy = false
    @State private var handled: Set<String> = []
    @State private var note: String?
    /// 0...1: how far the stamp is pressing the slip down.
    @State private var press: CGFloat = 0
    @State private var slide: CGFloat = 0
    @State private var lastTick = 0
    @State private var shown = false

    init(approval: Approval, team: TeamModel) {
        self.team = team
        _current = State(initialValue: approval)
    }

    private var bot: BotInfo? { team.bots.first { $0.id == current.botId } }
    private var name: String { bot?.name ?? "Bot" }
    private var answerable: Bool { current.answerable != false }
    private var waiting: Int { team.approvals.filter { $0.id != current.id && !handled.contains($0.id) }.count }

    var body: some View {
        ZStack {
            Aurora(seed: 5.2).ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    if waiting > 0 {
                        Text("后面还有 \(waiting) 张")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x1B1B22))
                            .padding(.horizontal, 14)
                            .frame(height: 34)
                            .glassEffect(.regular, in: .capsule)
                            .transition(.opacity)
                    }
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
                .padding(.horizontal, 20)
                .padding(.top, 8)

                Spacer(minLength: 12)

                ZStack {
                    if waiting > 0 {
                        SlipShape()
                            .fill(.white)
                            .frame(width: 300, height: 300)
                            .rotationEffect(.degrees(5))
                            .offset(x: 14, y: 12)
                            .blur(radius: 1.5)
                            .opacity(0.8)
                            .shadow(color: Color(hex: 0x141432).opacity(0.10), radius: 14, y: 14)
                            .transition(.opacity)
                    }
                    slip
                        .scaleEffect(1 - 0.035 * press)
                        .rotationEffect(.degrees(Double(-4 - 2 * press)))
                        .offset(y: 12 * press)
                        .id(current.id)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.86).combined(with: .opacity).combined(with: .offset(x: 10, y: 30)),
                            removal: .offset(x: 300, y: -520).combined(with: .opacity)
                        ))
                }
                .scaleEffect(shown ? 1 : 0.9)
                .opacity(shown ? 1 : 0)
                .blur(radius: shown ? 0 : 10)

                Spacer(minLength: 12)

                VStack(spacing: 10) {
                    Text(title)
                        .font(.system(size: 30, weight: .heavy))
                        .tracking(-0.5)
                        .foregroundStyle(Color(hex: 0x0B0B0F))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .contentTransition(.opacity)
                    Text(note ?? subtitle)
                        .font(.system(size: 17))
                        .foregroundStyle(note == nil ? Color(hex: 0x2A2A33) : Color(hex: 0xB4232F))
                        .multilineTextAlignment(.center)
                        .contentTransition(.opacity)
                    controls
                        .padding(.top, 18)
                        .frame(height: 124, alignment: .top)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }
        }
        .preferredColorScheme(.light)
        .fontDesign(.rounded)
        .onAppear {
            Haptics.prepare()
            withAnimation(.spring(response: 0.6, dampingFraction: 0.72).delay(0.1)) { shown = true }
        }
        .onChange(of: team.approvals) {
            // Answered somewhere else while this slip was open.
            guard verdict == nil, !busy, !team.approvals.contains(where: { $0.id == current.id }) else { return }
            handled.insert(current.id)
            withAnimation(.smooth) { note = "这张单子已经在别处处理了。" }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { advance() }
        }
    }

    private var title: String {
        switch verdict {
        case .allowed: return "盖章，放行"
        case .rejected: return "已拒绝"
        case nil: return "\(name)在等你点头"
        }
    }

    private var subtitle: String {
        switch verdict {
        case .allowed: return "\(name)已经继续干活。"
        case .rejected: return "\(name)不会做这件事。"
        case nil: return answerable ? "向右滑到底，就算批准。" : "这张单子现在答不了。"
        }
    }

    @ViewBuilder
    private var controls: some View {
        if verdict == nil && answerable {
            VStack(spacing: 6) {
                SlideTrack(progress: $slide, onTick: tick) { answer(allow: true) }
                    .disabled(busy)
                Button {
                    Haptics.light()
                    answer(allow: false)
                } label: {
                    Text("不批准")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x3A3A45))
                        .frame(height: 46)
                        .padding(.horizontal, 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(busy)
                .opacity(busy ? 0.4 : 1)
            }
            .transition(.blurReplace)
        }
    }

    // MARK: The slip

    private var slip: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("审 批 单")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(2)
                Spacer()
                Text(Self.clock(current.at.map { Date(timeIntervalSince1970: $0 / 1000) } ?? Date(), "HH:mm"))
                    .font(.system(size: 12, design: .monospaced))
            }
            .foregroundStyle(Color(hex: 0x4A4A55))

            HStack(spacing: 12) {
                Face(tone: BadgeLook.tone(named: bot?.color), size: 46, mood: verdict == nil ? .asking : .happy, ears: Ears.of(name))
                    .padding(.top, 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text("申请人").font(.system(size: 13)).foregroundStyle(Color(hex: 0x4A4A55))
                    Text(name).font(.system(size: 20, weight: .heavy)).lineLimit(1)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("想做的事").font(.system(size: 13)).foregroundStyle(Color(hex: 0x4A4A55))
                if let tool = current.tool, !tool.isEmpty {
                    Text(tool).font(.system(size: 17, weight: .semibold)).lineLimit(2)
                }
                if let text = current.detail?.text, !text.isEmpty {
                    Text(text).font(.system(size: 15)).lineLimit(4)
                }
                if let reason = current.reason, !reason.isEmpty {
                    Text(reason).font(.system(size: 14)).foregroundStyle(Color(hex: 0x3A3A45)).lineLimit(4)
                }
                if let code = current.detail?.code, !code.isEmpty {
                    Text(code)
                        .font(.system(size: 13, design: .monospaced))
                        .lineLimit(4)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(hex: 0xF1F0F6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }

            DashLine()
                .stroke(Color(hex: 0xCFCFD8), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                .frame(height: 1.5)

            VStack(alignment: .leading, spacing: 2) {
                Text("批准人").font(.system(size: 13)).foregroundStyle(Color(hex: 0x4A4A55))
                Text("你").font(.system(size: 17, weight: .semibold))
            }
            .frame(height: 62, alignment: .bottomLeading)
        }
        .foregroundStyle(Color(hex: 0x0B0B0F))
        .padding(.init(top: 26, leading: 20, bottom: 22, trailing: 20))
        .frame(width: 300)
        .background(SlipShape().fill(.white))
        .overlay(alignment: .bottomTrailing) {
            Stamp(
                word: verdict == .rejected ? "已拒绝" : "已批准",
                date: Self.clock(stampedAt, "MM-dd HH:mm"),
                ink: verdict == .rejected ? Color(hex: 0x3A3A45) : Color(hex: 0xC4222F)
            )
            .scaleEffect(verdict != nil ? 1 : 2.8)
            .opacity(verdict != nil ? 1 : 0)
            .rotationEffect(.degrees(-14))
            .padding(.trailing, 16)
            .padding(.bottom, 14)
        }
        .shadow(color: Color(hex: 0x141432).opacity(0.18 - 0.06 * Double(press)), radius: 24 - 10 * press, y: 24 - 12 * press)
    }

    private static func clock(_ date: Date, _ format: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    // MARK: Answering

    private func tick(_ step: Int) {
        if step != lastTick {
            lastTick = step
            Haptics.tick(0.45 + 0.07 * CGFloat(step))
        }
    }

    /// The stamp only falls once the computer has taken the answer.
    private func answer(allow: Bool) {
        guard !busy else { return }
        busy = true
        note = nil
        let asked = current
        Task {
            do {
                try await team.answer(asked, allow: allow)
                handled.insert(asked.id)
                stamp(allow ? .allowed : .rejected)
            } catch {
                Haptics.lock()
                lastTick = 0
                withAnimation(.spring(response: 0.42, dampingFraction: 0.6)) {
                    slide = 0
                    note = "这张单子已经不在了。"
                }
                handled.insert(asked.id)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { advance() }
            }
        }
    }

    /// The stamp falls, lands with a thud, and the slip gives under it.
    private func stamp(_ result: Verdict) {
        stampedAt = Date()
        withAnimation(.spring(response: 0.24, dampingFraction: 0.62)) { verdict = result }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.11) {
            if result == .allowed { Haptics.thud() } else { Haptics.lock() }
            withAnimation(.spring(response: 0.1, dampingFraction: 0.7)) { press = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.38)) { press = 0 }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { advance() }
    }

    /// On to the next slip, or back when there is none.
    private func advance() {
        guard let next = team.approvals.first(where: { !handled.contains($0.id) }) else {
            dismiss()
            return
        }
        lastTick = 0
        withAnimation(.spring(response: 0.55, dampingFraction: 0.8)) {
            current = next
            verdict = nil
            slide = 0
            note = nil
            busy = false
        }
    }
}

/// The round seal.
private struct Stamp: View {
    let word: String
    let date: String
    let ink: Color

    var body: some View {
        ZStack {
            Circle().strokeBorder(ink, lineWidth: 4)
            Circle().strokeBorder(ink, lineWidth: 1.5).padding(7)
            VStack(spacing: 2) {
                Text(word)
                    .font(.system(size: 24, weight: .black))
                    .tracking(2)
                Text(date)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
            }
            .foregroundStyle(ink)
        }
        .frame(width: 108, height: 108)
        .opacity(0.92)
        .accessibilityHidden(true)
    }
}

/// Slide to approve: a glass track with a knob that springs back unless it reaches the end.
private struct SlideTrack: View {
    @Binding var progress: CGFloat
    let onTick: (Int) -> Void
    let onDone: () -> Void

    private let height: CGFloat = 62
    private let knob: CGFloat = 52

    var body: some View {
        GeometryReader { proxy in
            let travel = max(1, proxy.size.width - knob - 10)
            ZStack(alignment: .leading) {
                Text("滑动批准")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x3A3A45))
                    .frame(maxWidth: .infinity)
                    .opacity(1 - Double(progress) * 1.6)
                Capsule()
                    .fill(Color(hex: 0x1F6AE8).opacity(0.18))
                    .frame(width: knob + 10 + travel * progress, height: height)
                Circle()
                    .fill(LinearGradient(colors: [Color(hex: 0x2A6FE6), Color(hex: 0x1756CC)], startPoint: .top, endPoint: .bottom))
                    .overlay {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 19, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: knob, height: knob)
                    .shadow(color: Color(hex: 0x1756CC).opacity(0.4), radius: 8, y: 5)
                    .scaleEffect(1 + 0.06 * progress)
                    .offset(x: 5 + travel * progress)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let next = max(0, min(1, value.translation.width / travel))
                                progress = next
                                onTick(Int(next * 8))
                            }
                            .onEnded { _ in
                                if progress > 0.86 {
                                    Haptics.lock()
                                    withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) { progress = 1 }
                                    onDone()
                                } else {
                                    Haptics.tick(0.5)
                                    withAnimation(.spring(response: 0.42, dampingFraction: 0.6)) { progress = 0 }
                                }
                            }
                    )
                    .accessibilityLabel("滑动批准")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { onDone() }
            }
            .frame(height: height)
            .glassEffect(.regular, in: .capsule)
        }
        .frame(height: height)
    }
}

private struct DashLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}
