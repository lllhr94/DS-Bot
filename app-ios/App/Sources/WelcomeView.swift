import SwiftUI

private struct Hang {
    let look: BadgeLook
    /// Where the pivot sits across the screen, 0...1.
    let x: CGFloat
    let strap: CGFloat
    let scale: CGFloat
    let blur: CGFloat
}

private let ready = Color(hex: 0x34C98A)
private let busy = Color(hex: 0xF5A623)

private let hangs: [Hang] = [
    Hang(look: BadgeLook(name: "墨墨", role: "写东西 · 改稿子", status: "空闲", light: ready, tone: 0xC9670F), x: 0.07, strap: 74, scale: 0.68, blur: 3),
    Hang(look: BadgeLook(name: "饭团", role: "吃什么 · 怎么做", status: "等你批准", light: busy, tone: 0x0E9684, mood: .asking), x: 0.90, strap: 50, scale: 0.66, blur: 2.5),
    Hang(look: BadgeLook(name: "团子", role: "贴身助理", status: "随时待命", light: ready, tone: 0x5563E6), x: 0.27, strap: 156, scale: 1, blur: 0),
    Hang(look: BadgeLook(name: "小探", role: "查资料 · 逛网页", status: "正在干活", light: Color(hex: 0x5B8DEF), tone: 0xD3458B, mood: .busy), x: 0.73, strap: 268, scale: 1, blur: 0),
]

struct WelcomeView: View {
    var onStart: () -> Void
    var onDemo: () -> Void

    @StateObject private var sway = Sway(lengths: hangs.map { Double($0.strap) + 110 })
    @State private var shown = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                ForEach(Array(hangs.enumerated()), id: \.offset) { index, hang in
                    HangingBadge(
                        hang: hang,
                        angle: sway.bobs[index].angle,
                        sheen: sway.rest,
                        pivotX: proxy.size.width * hang.x,
                        onDrag: { angle, velocity in sway.hold(index, angle: angle, velocity: velocity) },
                        onRelease: { sway.release(index) }
                    )
                    .offset(x: proxy.size.width * (hang.x - 0.5))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .coordinateSpace(name: "stage")
        }
        .ignoresSafeArea()
        .overlay(alignment: .bottom) { footer }
        .onAppear {
            Haptics.prepare()
            sway.start()
            withAnimation(.smooth(duration: 0.9).delay(0.25)) { shown = true }
        }
        .onDisappear { sway.stop() }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Text("口袋里的 Bot 团队")
                .font(.system(size: 30, weight: .heavy))
                .tracking(-0.5)
                .foregroundStyle(Color(hex: 0x0B0B0F))
            Text("它们住在你的手机里，记得你，也会主动找你。")
                .font(.system(size: 17))
                .foregroundStyle(Color(hex: 0x2A2A33))
                .multilineTextAlignment(.center)
            Button {
                Haptics.light()
                onStart()
            } label: {
                Text("开始")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .tint(Color(hex: 0x1F6AE8))
            .padding(.top, 18)
            Button {
                Haptics.light()
                onDemo()
            } label: {
                Text("先逛逛")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x2A2A33))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 4)
        .blur(radius: shown ? 0 : 12)
        .opacity(shown ? 1 : 0)
        .offset(y: shown ? 0 : 14)
    }
}

private struct HangingBadge: View {
    let hang: Hang
    let angle: Double
    let sheen: Double
    let pivotX: CGFloat
    let onDrag: (Double, Double) -> Void
    let onRelease: () -> Void

    @State private var lastAngle: Double = 0
    @State private var lastTime = Date()

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(LinearGradient(colors: [Color.shade(hang.look.tone, lift: 0.25), Color.shade(hang.look.tone, lift: 0.45)], startPoint: .top, endPoint: .bottom))
                .frame(width: 12, height: hang.strap)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0xE3E5EC), Color(hex: 0xB9BDCA)], startPoint: .top, endPoint: .bottom))
                .frame(width: 20, height: 14)
            BadgeCard(look: hang.look, sheen: sheen)
                .contentShape(Rectangle())
                .gesture(drag)
        }
        .scaleEffect(hang.scale, anchor: .top)
        .rotationEffect(.radians(angle), anchor: .top)
        .blur(radius: hang.blur)
        .opacity(hang.blur > 0 ? 0.88 : 1)
        .allowsHitTesting(hang.blur == 0)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("stage"))
            .onChanged { value in
                let dx = Double(value.location.x - pivotX)
                let dy = Double(max(value.location.y, 40))
                let next = -atan2(dx, dy)
                let now = Date()
                let dt = max(now.timeIntervalSince(lastTime), 1.0 / 120.0)
                let velocity = value.translation == .zero ? 0 : (next - lastAngle) / dt
                if value.translation == .zero { Haptics.grab() }
                lastAngle = next
                lastTime = now
                onDrag(next, velocity)
            }
            .onEnded { _ in
                Haptics.tick(0.9)
                onRelease()
            }
    }
}
