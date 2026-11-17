import SwiftUI

/// Stage 0: three screens of made-up content, to settle the look before anything real is built on it.
struct ProtoRoot: View {
    enum Page: String, CaseIterable {
        case chat = "絮语"
        case home = "案头"
        case note = "笺"
        case whale = "鲸鱼"
    }

    @State private var page: Page = .home
    @Namespace private var marker

    var body: some View {
        ZStack(alignment: .bottom) {
            Ink.paper.ignoresSafeArea()
            Group {
                switch page {
                case .chat: ProtoChat()
                case .home: ProtoHome(open: { go(.chat) })
                case .note: ProtoNote()
                case .whale: ProtoWhale()
                }
            }
            .transition(.blurReplace)
            .padding(.bottom, page == .chat ? 0 : 64)
            if page != .chat { bar }
        }
        .overlay(alignment: .topTrailing) {
            if page == .chat {
                Button { go(.home) } label: {
                    Text("样机")
                        .font(Ink.footnote)
                        .foregroundStyle(Ink.inkSoft)
                        .padding(.horizontal, Ink.Space.s)
                        .frame(height: 24)
                        .background(Ink.paperRaised.opacity(0.9), in: .capsule)
                }
                .buttonStyle(PressStyle())
                .padding(.trailing, Ink.Space.page)
                .padding(.top, 58)
            }
        }
        .tint(Ink.accent)
    }

    private func go(_ next: Page) {
        withAnimation(Ink.Motion.settle) { page = next }
    }

    private var bar: some View {
        HStack(spacing: Ink.Space.xs) {
            ForEach(Page.allCases, id: \.self) { item in
                Button { go(item) } label: {
                    Text(item.rawValue)
                        .font(Ink.label)
                        .foregroundStyle(page == item ? Ink.ink : Ink.inkSoft)
                        .padding(.horizontal, Ink.Space.l)
                        .frame(height: 38)
                        .background {
                            if page == item {
                                Capsule().fill(Ink.paperRaised).matchedGeometryEffect(id: "page", in: marker)
                            }
                        }
                }
                .buttonStyle(PressStyle())
            }
        }
        .padding(Ink.Space.xs)
        .glassEffect(.regular, in: .capsule)
        .padding(.bottom, Ink.Space.s)
    }
}

/// 案头: the home screen.
struct ProtoHome: View {
    var open: () -> Void

    private struct Thread: Identifiable {
        let id: Int
        let title: String
        let preview: String
        let when: String
        let wash: Int
    }

    private let threads = [
        Thread(id: 0, title: "周末去哪儿走走", preview: "磁器口周六多云转小雨，记得带伞。", when: "方才", wash: 0),
        Thread(id: 1, title: "十月的花销", preview: "一共花了 6,842，房租占了近一半。", when: "昨日", wash: 3),
        Thread(id: 2, title: "给外婆的信", preview: "第二段我改得口语了些，你看看。", when: "周一", wash: 1),
        Thread(id: 3, title: "注安案例第三章", preview: "这一章常考的三个点我列出来了。", when: "上周", wash: 2),
    ]

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<11: "晨安"
        case 11..<13: "午安"
        case 13..<18: "午后好"
        case 18..<23: "晚上好"
        default: "夜深了"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: Ink.Space.s) {
                        Text(greeting)
                            .font(Ink.display)
                            .foregroundStyle(Ink.ink)
                        Text("今天想聊点什么？")
                            .font(Ink.reading)
                            .foregroundStyle(Ink.inkSoft)
                    }
                    Spacer()
                    Whale(size: 96, pose: .idle)
                }
                .padding(.top, Ink.Space.xxl)

                ScrollView(.horizontal) {
                    HStack(spacing: Ink.Space.s) {
                        companion("团子", wash: 0, picked: true)
                        companion("小探", wash: 2, picked: false)
                        companion("墨墨", wash: 1, picked: false)
                        companion("饭团", wash: 3, picked: false)
                    }
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
                .padding(.top, Ink.Space.xl)

                HStack(spacing: Ink.Space.s) {
                    Image(systemName: "envelope")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Ink.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("来信").font(Ink.footnote).foregroundStyle(Ink.inkSoft)
                        Text("团子约好 18:30 提醒你泡黄豆").font(Ink.secondary).foregroundStyle(Ink.ink)
                    }
                    Spacer()
                }
                .padding(Ink.Space.l)
                .paperCard()
                .padding(.top, Ink.Space.xl)

                Text("近来的絮语")
                    .font(Ink.title)
                    .foregroundStyle(Ink.ink)
                    .padding(.top, Ink.Space.xxl)
                    .padding(.bottom, Ink.Space.s)

                ForEach(threads) { thread in
                    Button(action: open) {
                        HStack(alignment: .top, spacing: Ink.Space.m) {
                            Whale(size: 28, wash: Ink.washes[thread.wash], still: true)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: Ink.Space.xs) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(thread.title).font(Ink.readingBold).foregroundStyle(Ink.ink)
                                    Spacer()
                                    Text(thread.when).font(Ink.footnote).foregroundStyle(Ink.inkFaint)
                                }
                                Text(thread.preview)
                                    .font(Ink.secondary)
                                    .foregroundStyle(Ink.inkSoft)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.vertical, Ink.Space.m)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    if thread.id != threads.count - 1 {
                        Rectangle().fill(Ink.rule).frame(height: 1).padding(.leading, 40)
                    }
                }
            }
            .padding(.horizontal, Ink.Space.page)
            .padding(.bottom, Ink.Space.huge)
        }
        .scrollIndicators(.hidden)
    }

    private func companion(_ name: String, wash: Int, picked: Bool) -> some View {
        Button(action: open) {
            HStack(spacing: Ink.Space.s) {
                Whale(size: 28, wash: Ink.washes[wash], still: true)
                Text(name).font(Ink.label).foregroundStyle(Ink.ink)
            }
            .padding(.leading, Ink.Space.xs + 2)
            .padding(.trailing, Ink.Space.l)
            .frame(height: 40)
            .background(picked ? Ink.paperRaised : .clear, in: .capsule)
            .overlay(Capsule().strokeBorder(picked ? Ink.accent.opacity(0.5) : Ink.rule, lineWidth: 1))
        }
        .buttonStyle(PressStyle())
    }
}

/// 笺: a reply set as a page to keep or share.
struct ProtoNote: View {
    private enum Theme: String, CaseIterable {
        case paper = "纸"
        case ink = "墨"
        case blossom = "樱"

        var ground: Color {
            switch self {
            case .paper: Color(hex: 0xF7F3EA)
            case .ink: Color(hex: 0x1F1D1A)
            case .blossom: Color(hex: 0xF8ECEA)
            }
        }

        var words: Color {
            switch self {
            case .paper: Color(hex: 0x3A4A5A)
            case .ink: Color(hex: 0xE6DFD1)
            case .blossom: Color(hex: 0x6A4650)
            }
        }

        var line: Color { words.opacity(0.18) }
    }

    @State private var theme: Theme = .paper

    var body: some View {
        ScrollView {
            VStack(spacing: Ink.Space.xl) {
                sheet
                    .clipShape(.rect(cornerRadius: Ink.Radius.card))
                    .shadow(color: .black.opacity(0.10), radius: 18, y: 10)
                    .padding(.top, Ink.Space.xl)

                HStack(spacing: Ink.Space.s) {
                    ForEach(Theme.allCases, id: \.self) { item in
                        Button {
                            withAnimation(Ink.Motion.settle) { theme = item }
                        } label: {
                            HStack(spacing: Ink.Space.s) {
                                Circle()
                                    .fill(item.ground)
                                    .overlay(Circle().strokeBorder(Ink.rule, lineWidth: 1))
                                    .frame(width: 18, height: 18)
                                Text(item.rawValue).font(Ink.label).foregroundStyle(Ink.ink)
                            }
                            .padding(.horizontal, Ink.Space.l)
                            .frame(height: 40)
                            .background(theme == item ? Ink.paperRaised : .clear, in: .capsule)
                            .overlay(Capsule().strokeBorder(theme == item ? Ink.accent.opacity(0.5) : Ink.rule, lineWidth: 1))
                        }
                        .buttonStyle(PressStyle())
                    }
                }
            }
            .padding(.horizontal, Ink.Space.page)
            .padding(.bottom, Ink.Space.huge)
        }
        .scrollIndicators(.hidden)
    }

    private var sheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("潮声")
                .font(Ink.serif(40, bold: true, relativeTo: .largeTitle))
                .foregroundStyle(theme.words)
                .padding(.top, Ink.Space.huge)
            Rectangle().fill(theme.line).frame(height: 1).padding(.vertical, Ink.Space.xl)
            VStack(alignment: .leading, spacing: Ink.Space.l + 2) {
                Text("潮水从不赶路。它只是按时来，按时走，像一个守信的老朋友。")
                Text("你站在岸上听，以为它在说话。其实它只是把远处的事，一遍一遍搬到你脚边：某条船刚刚经过，某阵风昨夜来过，某片云在很远的地方化成了雨。")
                Text("听久了，人会慢下来。不是因为没有要紧的事，是因为忽然明白，要紧的事也会像潮水一样，退了还会再来。")
            }
            .font(Ink.serif(18, relativeTo: .body))
            .lineSpacing(10)
            .foregroundStyle(theme.words)
            HStack(spacing: Ink.Space.s) {
                Spacer()
                Whale(size: 22, wash: theme.words.opacity(0.14), tone: theme.words.opacity(0.7), still: true)
                Text("Clio")
                    .font(Ink.serif(14, relativeTo: .footnote))
                    .foregroundStyle(theme.words.opacity(0.6))
                Spacer()
            }
            .padding(.top, Ink.Space.huge)
            .padding(.bottom, Ink.Space.xxl)
        }
        .padding(.horizontal, Ink.Space.xxl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.ground)
    }
}

/// The whale's three outlines and four poses, the colors, and whether the reading face was found.
struct ProtoWhale: View {
    @AppStorage("whale.look") private var picked = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Ink.Space.xl) {
                Text("挑一只鲸鱼")
                    .font(Ink.display)
                    .foregroundStyle(Ink.ink)
                    .padding(.top, Ink.Space.xxl)
                Text("点一下选中，其他页面会跟着换。")
                    .font(Ink.secondary)
                    .foregroundStyle(Ink.inkSoft)

                ForEach(0..<WhaleLook.looks.count, id: \.self) { index in
                    Button {
                        withAnimation(Ink.Motion.unfold) { picked = index }
                    } label: {
                        VStack(alignment: .leading, spacing: Ink.Space.m) {
                            HStack {
                                Text("\(index + 1) · \(WhaleLook.names[index])")
                                    .font(Ink.readingBold)
                                    .foregroundStyle(Ink.ink)
                                Spacer()
                                Image(systemName: picked == index ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(picked == index ? Ink.accent : Ink.inkFaint)
                                    .contentTransition(.symbolEffect(.replace))
                            }
                            HStack(spacing: Ink.Space.m) {
                                Whale(size: 96, pose: .idle, look: index)
                                VStack(alignment: .leading, spacing: Ink.Space.s) {
                                    HStack(spacing: Ink.Space.m) {
                                        ForEach(WhalePose.allCases, id: \.self) { pose in
                                            VStack(spacing: Ink.Space.xs) {
                                                Whale(size: 44, pose: pose, look: index)
                                                Text(pose.word).font(Ink.footnote).foregroundStyle(Ink.inkSoft)
                                            }
                                        }
                                    }
                                    HStack(spacing: Ink.Space.s) {
                                        ForEach(0..<Ink.washes.count, id: \.self) { wash in
                                            Whale(size: 28, wash: Ink.washes[wash], look: index, still: true)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(Ink.Space.l)
                        .paperCard()
                        .overlay(RoundedRectangle(cornerRadius: Ink.Radius.card).strokeBorder(picked == index ? Ink.accent.opacity(0.6) : .clear, lineWidth: 2))
                    }
                    .buttonStyle(PressStyle())
                }

                Text("颜色").font(Ink.title).foregroundStyle(Ink.ink).padding(.top, Ink.Space.s)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Ink.Space.s), count: 4), spacing: Ink.Space.s) {
                    swatch("纸", Ink.paper)
                    swatch("卡片", Ink.paperRaised)
                    swatch("我的话", Ink.mine)
                    swatch("细线", Ink.rule)
                    swatch("墨", Ink.ink)
                    swatch("淡墨", Ink.inkSoft)
                    swatch("黛蓝", Ink.accent)
                    swatch("蓝晕", Ink.accentWash)
                }

                Text(Ink.hasSongti ? "阅读字体：宋体，已找到。" : "阅读字体：没找到宋体，现在用的是系统衬线体。请把这一行截图给我。")
                    .font(Ink.footnote)
                    .foregroundStyle(Ink.hasSongti ? Ink.inkSoft : Ink.stop)
            }
            .padding(.horizontal, Ink.Space.page)
            .padding(.bottom, Ink.Space.huge)
        }
        .scrollIndicators(.hidden)
    }

    private func swatch(_ name: String, _ color: Color) -> some View {
        VStack(spacing: Ink.Space.xs) {
            RoundedRectangle(cornerRadius: Ink.Radius.small)
                .fill(color)
                .overlay(RoundedRectangle(cornerRadius: Ink.Radius.small).strokeBorder(Ink.rule, lineWidth: 1))
                .frame(height: 44)
            Text(name).font(Ink.footnote).foregroundStyle(Ink.inkSoft)
        }
    }
}
