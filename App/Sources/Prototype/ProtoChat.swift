import SwiftUI

/// 絮语: the chat screen, with made-up content that shows every kind of row.
struct ProtoChat: View {
    @State private var traceOpen = false
    @State private var shown: Double = 0
    @State private var writing = false
    @State private var draft = ""
    @FocusState private var typing: Bool

    private let streamed = "磁器口这个周六**多云转小雨**，气温 14 到 19 度。上午人少，适合慢慢逛；午后有雨，记得带伞。\n\n日程我已经替你记下了，出门前一小时会叫你。"

    private var pose: WhalePose {
        if writing { return .writing }
        if typing { return .thinking }
        return .idle
    }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: Ink.Space.xl) {
                    mine("这周六想和朋友去磁器口，帮我看看天气，顺便记进日历")
                    trace
                    reply
                    table
                    code
                    files
                    footer
                }
                .padding(.horizontal, Ink.Space.page)
                .padding(.top, 76)
                .padding(.bottom, 150)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            header
        }
        .safeAreaInset(edge: .bottom) { composer }
        .onAppear { play() }
    }

    // MARK: Top bar

    private var header: some View {
        HStack(spacing: Ink.Space.s) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Ink.ink)
                .frame(width: 38, height: 38)
                .glassEffect(.regular, in: .circle)
            VStack(alignment: .leading, spacing: 0) {
                Text("周末去哪儿走走").font(.system(size: 15, weight: .semibold)).foregroundStyle(Ink.ink)
                HStack(spacing: 4) {
                    Circle().fill(writing ? Ink.accent : Ink.ok).frame(width: 6, height: 6)
                    Text(writing ? "团子 · 落笔" : "团子 · 闲坐")
                        .font(Ink.footnote)
                        .foregroundStyle(Ink.inkSoft)
                        .contentTransition(.opacity)
                }
            }
            .glassChip()
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: "sparkle").font(.system(size: 12, weight: .semibold))
                Text("deepseek").font(.system(size: 14, weight: .medium))
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(Ink.ink)
            .glassChip()
            Image(systemName: "square.and.pencil")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Ink.ink)
                .frame(width: 38, height: 38)
                .glassEffect(.regular, in: .circle)
        }
        .padding(.horizontal, Ink.Space.l)
        .padding(.top, Ink.Space.s)
    }

    // MARK: Rows

    private func mine(_ text: String) -> some View {
        Text(text)
            .font(Ink.label)
            .foregroundStyle(Ink.ink)
            .lineSpacing(4)
            .padding(.horizontal, Ink.Space.l)
            .padding(.vertical, Ink.Space.m)
            .background(Ink.mine, in: .rect(cornerRadius: 18))
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, Ink.Space.huge)
    }

    /// 行迹: one line when closed, a timeline when open.
    private var trace: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(Ink.Motion.unfold) { traceOpen.toggle() }
            } label: {
                HStack(spacing: Ink.Space.s) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Ink.ok)
                    Text("行迹 · 3 步 · 23 秒")
                        .font(Ink.secondary)
                        .foregroundStyle(Ink.inkSoft)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Ink.inkFaint)
                        .rotationEffect(.degrees(traceOpen ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            if traceOpen {
                VStack(alignment: .leading, spacing: 0) {
                    step("magnifyingglass", "寻访", "重庆 周六 天气", "2 秒", last: false)
                    step("globe", "远游", "weather.com.cn", "6 秒", last: false)
                    step("calendar", "落印", "新建日程 · 周六 10:00 去磁器口", "已应许", last: true)
                }
                .padding(.top, Ink.Space.m)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func step(_ icon: String, _ name: String, _ detail: String, _ time: String, last: Bool) -> some View {
        HStack(alignment: .top, spacing: Ink.Space.m) {
            VStack(spacing: 0) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Ink.accent)
                    .frame(width: 24, height: 24)
                    .background(Ink.accentWash, in: .circle)
                if !last { Rectangle().fill(Ink.rule).frame(width: 1).frame(maxHeight: .infinity) }
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(name).font(.system(size: 14, weight: .semibold)).foregroundStyle(Ink.ink)
                    Spacer()
                    Text(time).font(Ink.footnote).foregroundStyle(Ink.inkFaint)
                }
                Text(detail).font(Ink.secondary).foregroundStyle(Ink.inkSoft)
            }
            .padding(.bottom, last ? 0 : Ink.Space.l)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// A companion's words sit straight on the paper, no bubble.
    private var reply: some View {
        Text((try? AttributedString(markdown: streamed, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(streamed))
            .font(Ink.reading)
            .lineSpacing(Ink.leading)
            .foregroundStyle(Ink.ink)
            .textRenderer(FadeIn(shown: shown))
            .frame(maxWidth: .infinity, alignment: .leading)
            .onTapGesture { play() }
    }

    private var table: some View {
        VStack(spacing: 0) {
            row("时段", "天气", "气温", head: true)
            Rectangle().fill(Ink.rule).frame(height: 1)
            row("上午", "多云", "14–17°", head: false)
            Rectangle().fill(Ink.rule).frame(height: 1)
            row("午后", "小雨", "17–19°", head: false)
            Rectangle().fill(Ink.rule).frame(height: 1)
            row("夜里", "阴", "15°", head: false)
        }
        .paperCard()
    }

    private func row(_ a: String, _ b: String, _ c: String, head: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach([a, b, c], id: \.self) { cell in
                Text(cell)
                    .font(head ? .system(size: 14, weight: .semibold) : Ink.secondary)
                    .foregroundStyle(head ? Ink.ink : Ink.inkSoft)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, Ink.Space.l)
        .padding(.vertical, Ink.Space.m)
    }

    private var code: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("python").font(Ink.footnote).foregroundStyle(Ink.inkSoft)
                Spacer()
                Image(systemName: "doc.on.doc").font(.system(size: 12)).foregroundStyle(Ink.inkSoft)
            }
            .padding(.horizontal, Ink.Space.l)
            .frame(height: 34)
            Rectangle().fill(Ink.rule).frame(height: 1)
            Text("def umbrella(rain: float) -> bool:\n    return rain > 0.3")
                .font(Ink.code)
                .foregroundStyle(Ink.ink)
                .lineSpacing(4)
                .padding(Ink.Space.l)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .paperCard()
    }

    private var files: some View {
        VStack(alignment: .leading, spacing: Ink.Space.m) {
            HStack(spacing: Ink.Space.s) {
                Image(systemName: "shippingbox").font(.system(size: 14, weight: .medium)).foregroundStyle(Ink.accent)
                Text("放在书案上的 2 样东西").font(.system(size: 14, weight: .semibold)).foregroundStyle(Ink.ink)
            }
            file("calendar", "周六 10:00 · 去磁器口", "日程 · 提前一小时提醒")
            Rectangle().fill(Ink.rule).frame(height: 1)
            file("doc.text", "磁器口半日路线.md", "书案 · 1.2 KB")
        }
        .padding(Ink.Space.l)
        .paperCard()
    }

    private func file(_ icon: String, _ name: String, _ note: String) -> some View {
        HStack(spacing: Ink.Space.m) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Ink.accent)
                .frame(width: 34, height: 34)
                .background(Ink.accentWash, in: .rect(cornerRadius: Ink.Radius.small))
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 15, weight: .medium)).foregroundStyle(Ink.ink)
                Text(note).font(Ink.footnote).foregroundStyle(Ink.inkSoft)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(Ink.inkFaint)
        }
    }

    private var footer: some View {
        HStack(spacing: Ink.Space.xl) {
            ForEach(["doc.on.doc", "arrow.clockwise", "speaker.wave.2", "scroll"], id: \.self) { icon in
                Button {} label: {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Ink.inkSoft)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
            }
            Spacer()
            Text("23 秒 · 3.4 千字")
                .font(Ink.footnote)
                .foregroundStyle(Ink.inkFaint)
        }
    }

    // MARK: Composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: Ink.Space.s) {
            TextField("同团子说点什么…", text: $draft, axis: .vertical)
                .font(Ink.label)
                .foregroundStyle(Ink.ink)
                .lineLimit(1...5)
                .focused($typing)
                .padding(.top, Ink.Space.xs)
            HStack(spacing: Ink.Space.s) {
                tool("plus")
                tool("globe", "联网")
                tool("shippingbox", "斗室")
                Spacer()
                Image(systemName: "mic")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Ink.inkSoft)
                    .frame(width: 34, height: 34)
                Button {
                    draft = ""
                    typing = false
                    play()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Ink.paper)
                        .frame(width: 34, height: 34)
                        .background(draft.isEmpty ? Ink.inkFaint : Ink.accent, in: .circle)
                }
                .buttonStyle(PressStyle())
            }
        }
        .padding(.horizontal, Ink.Space.l)
        .padding(.vertical, Ink.Space.m)
        .glassEffect(.regular, in: .rect(cornerRadius: Ink.Radius.sheet))
        .overlay(alignment: .topTrailing) {
            Whale(size: 44, pose: pose)
                .offset(x: -Ink.Space.l, y: -34)
                .animation(Ink.Motion.unfold, value: pose)
        }
        .padding(.horizontal, Ink.Space.m)
        .padding(.bottom, Ink.Space.s)
    }

    private func tool(_ icon: String, _ name: String? = nil) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 13, weight: .medium))
            if let name { Text(name).font(.system(size: 13, weight: .medium)) }
        }
        .foregroundStyle(Ink.inkSoft)
        .padding(.horizontal, name == nil ? 0 : Ink.Space.m)
        .frame(minWidth: 32, minHeight: 32)
        .overlay(Capsule().strokeBorder(Ink.rule, lineWidth: 1))
    }

    /// Plays the reply again, glyph by glyph.
    private func play() {
        let count = Double(streamed.count)
        shown = 0
        writing = true
        withAnimation(.linear(duration: count / 28)) { shown = count + 10 }
        DispatchQueue.main.asyncAfter(deadline: .now() + count / 28) {
            withAnimation(Ink.Motion.settle) { writing = false }
            Haptics.tick(0.5)
        }
    }
}
