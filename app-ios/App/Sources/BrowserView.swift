import DSLink
import SwiftUI

/// What a Bot's browser shows right now, read from the computer every moment or so.
/// The phone watches; working the browser by hand happens on the computer.
struct BrowserView: View {
    @ObservedObject var team: TeamModel
    let bot: BotInfo
    @Environment(\.dismiss) private var dismiss

    @State private var page: UIImage?
    @State private var title = ""
    @State private var address = ""
    @State private var problem: String?
    @State private var flat = false
    @State private var shown = false
    @State private var busy = false
    @State private var seen = Date()

    private var tone: UInt32 { BadgeLook.tone(named: bot.color) }
    private var hold: BrowserHold? { team.browserHolds[bot.id] }
    private var demo: Bool { team.phase == .demo }

    var body: some View {
        ZStack {
            Aurora(seed: 9.3).ignoresSafeArea()
            VStack(spacing: 0) {
                header
                Spacer(minLength: 10)
                window
                    .rotation3DEffect(.degrees(flat ? 0 : 7), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
                    .rotation3DEffect(.degrees(flat ? 0 : -11), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                    .rotationEffect(.degrees(flat ? 0 : -1.5))
                    .scaleEffect(shown ? (flat ? 1 : 0.9) : 0.8)
                    .opacity(shown ? 1 : 0)
                    .padding(.horizontal, flat ? 10 : 26)
                    .onTapGesture {
                        Haptics.tick(0.6)
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.72)) { flat.toggle() }
                    }
                    .accessibilityLabel("\(bot.name)的浏览器画面")
                    .accessibilityHint("点一下放平或立起来")
                Spacer(minLength: 10)
                footer
            }
        }
        .preferredColorScheme(.light)
        .fontDesign(.rounded)
        .onAppear {
            Haptics.prepare()
            withAnimation(.spring(response: 0.6, dampingFraction: 0.72).delay(0.1)) { shown = true }
        }
        .task {
            // One read at a time: the next starts a moment after the last one came back.
            while !Task.isCancelled {
                await read()
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }
    }

    // MARK: Parts

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                Haptics.light()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x0B0B0F))
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭")
            Face(tone: tone, size: 34, mood: hold?.by == "user" ? .happy : .busy, ears: Ears.of(bot.name))
                .padding(.top, 8)
                .padding(.horizontal, 3)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(bot.name)的浏览器")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color(hex: 0x0B0B0F))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Circle()
                        .fill(page != nil && problem == nil ? Color(hex: 0x34C98A) : Color(hex: 0xB9BDCA))
                        .frame(width: 7, height: 7)
                    Text(page != nil && problem == nil ? "实时画面" : "没有画面")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(hex: 0x3A3A45))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(height: 60)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, 14)
        .padding(.top, 4)
    }

    /// The browser as a floating window: a small bar with the address, then the page.
    private var window: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Circle().fill(Color(hex: 0xE8695E)).frame(width: 9, height: 9)
                    Circle().fill(Color(hex: 0xE9B44A)).frame(width: 9, height: 9)
                    Circle().fill(Color(hex: 0x5DBE6E)).frame(width: 9, height: 9)
                }
                Text(address.isEmpty ? (demo ? "example.com" : "还没有网址") : address)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: 0x3A3A45))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 26)
                    .background(.white, in: .capsule)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(hex: 0xF1F0F6))

            Group {
                if let page {
                    Image(uiImage: page)
                        .resizable()
                        .scaledToFit()
                        .transition(.opacity)
                } else if demo {
                    sample
                } else {
                    VStack(spacing: 12) {
                        if problem == nil {
                            ProgressView().controlSize(.large)
                        } else {
                            Face(tone: tone, size: 64, mood: .sleepy, ears: Ears.of(bot.name)).padding(.top, 16)
                        }
                        Text(problem ?? "正在取画面")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x3A3A45))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 300)
                }
            }
            .frame(maxWidth: .infinity)
            .background(.white)
        }
        .clipShape(.rect(cornerRadius: 22))
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.white)
                .shadow(color: Color(hex: 0x141432).opacity(0.22), radius: 26, y: 26)
        }
    }

    /// A made-up page for the demo team.
    private var sample: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: 6).fill(Color(hex: 0xD8D7E2)).frame(width: 170, height: 18)
            RoundedRectangle(cornerRadius: 5).fill(Color(hex: 0xECEBF2)).frame(height: 9)
            RoundedRectangle(cornerRadius: 5).fill(Color(hex: 0xECEBF2)).frame(height: 9).padding(.trailing, 30)
            RoundedRectangle(cornerRadius: 14)
                .fill(LinearGradient(colors: [Color(hex: 0xF4E9F0), Color(hex: 0xE9EEF9)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(height: 120)
                .overlay {
                    Text("演示团队没有真的浏览器\n连上电脑后这里是实时画面")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(hex: 0x3A3A45))
                        .multilineTextAlignment(.center)
                }
            RoundedRectangle(cornerRadius: 5).fill(Color(hex: 0xECEBF2)).frame(height: 9).padding(.trailing, 50)
            RoundedRectangle(cornerRadius: 5).fill(Color(hex: 0xECEBF2)).frame(height: 9).padding(.trailing, 110)
        }
        .padding(16)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            if !title.isEmpty {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color(hex: 0x0B0B0F))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            Text(note)
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: 0x3A3A45))
                .multilineTextAlignment(.center)
                .lineLimit(3)
            if !demo && team.browserOn {
                HStack(spacing: 10) {
                    if let callId = hold?.callId {
                        action("跳过", prominent: false) { await act("browser-give-back", ["botId": bot.id, "outcome": "skip", "callId": callId]) }
                        action("我弄好了", prominent: true) { await act("browser-give-back", ["botId": bot.id, "outcome": "done", "callId": callId]) }
                    } else if hold?.by == "user" {
                        action("交还给它", prominent: true) { await act("browser-give-back", ["botId": bot.id]) }
                    } else {
                        action("让它停下", prominent: false) { await act("browser-stop", ["botId": bot.id]) }
                        action("我来操作", prominent: true) { await act("browser-takeover", ["botId": bot.id]) }
                    }
                }
                .disabled(busy)
                .padding(.top, 6)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .animation(.smooth, value: hold)
    }

    private var note: String {
        if demo { return "点一下画面可以放平细看。" }
        if let hold {
            if hold.callId != nil { return hold.note ?? "\(bot.name)需要你在电脑上帮它操作一下，弄完告诉它。" }
            if hold.by == "user" { return "现在由你在电脑上操作，\(bot.name)在等。弄完点交还。" }
        }
        if page == nil { return "它用浏览器的时候，画面会出现在这里。" }
        return "手机上只能看。要亲手操作，点“我来操作”后到电脑上进行。"
    }

    private func action(_ label: String, prominent: Bool, run: @escaping () async -> Void) -> some View {
        Button {
            Haptics.grab()
            Task { await run() }
        } label: {
            Text(label)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(prominent ? .white : Color(hex: 0x0B0B0F))
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    prominent
                        ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x2A6FE6), Color(hex: 0x1756CC)], startPoint: .top, endPoint: .bottom))
                        : AnyShapeStyle(Color.white.opacity(0.7)),
                    in: .capsule
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: Reading and acting

    private func read() async {
        if demo { return }
        do {
            let frame = try await team.call("browser-frame", ["botId": bot.id], timeout: 20)
            guard let text = frame["data"] as? String, let data = Data(base64Encoded: text), let image = UIImage(data: data) else { return }
            withAnimation(.smooth(duration: 0.25)) {
                page = image
                problem = nil
            }
            title = frame["title"] as? String ?? ""
            address = frame["url"] as? String ?? ""
            seen = Date()
        } catch let failure as LinkError {
            switch failure.code {
            case "bot/not-found":
                // The browser closed: the last page would be a lie.
                withAnimation(.smooth) { page = nil }
                title = ""
                address = ""
                problem = "\(bot.name)现在没有打开浏览器"
            case "bot/browser-off":
                withAnimation(.smooth) { page = nil }
                problem = "这台电脑没有开启 Bot 浏览器"
            case "link/offline", "TRANSPORT_CLOSED", "RPC_TIMEOUT", "NOT_CONNECTED":
                // Keep the last page for a short while, then say the picture is stale.
                if page == nil || Date().timeIntervalSince(seen) > 10 { problem = "还没连上电脑" }
            default:
                if page == nil { problem = failure.message }
            }
        } catch {
            if page == nil { problem = "取不到画面" }
        }
    }

    private func act(_ endpoint: String, _ payload: [String: Any]) async {
        busy = true
        defer { busy = false }
        do {
            _ = try await team.call(endpoint, payload)
            Haptics.tick(0.8)
        } catch {
            Haptics.lock()
            problem = (error as? LinkError)?.message ?? "没做成"
        }
        await read()
    }
}
