import SwiftUI

private struct Hang {
    let bot: Bot
    /// Where the pivot sits across the screen, 0...1.
    let x: CGFloat
    let strap: CGFloat
    let scale: CGFloat
    let blur: CGFloat
}

private let hangs: [Hang] = [
    Hang(bot: .writer, x: 0.07, strap: 74, scale: 0.68, blur: 3),
    Hang(bot: .ops, x: 0.90, strap: 50, scale: 0.66, blur: 2.5),
    Hang(bot: .chief, x: 0.27, strap: 156, scale: 1, blur: 0),
    Hang(bot: .scout, x: 0.73, strap: 268, scale: 1, blur: 0),
]

struct WelcomeView: View {
    var onContinue: () -> Void

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
            Text("你的团队，随时待命")
                .font(.system(size: 30, weight: .heavy))
                .tracking(-0.5)
                .foregroundStyle(Color(hex: 0x0B0B0F))
            Text("把事情交给 Bot，需要你的时候再来找你。")
                .font(.system(size: 17))
                .foregroundStyle(Color(hex: 0x2A2A33))
                .multilineTextAlignment(.center)
            Text("拨一拨工牌，或者把手机歪一下")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(hex: 0x4A4A55))
                .padding(.top, 2)
            Button {
                Haptics.light()
                onContinue()
            } label: {
                Text("继续")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .tint(Color(hex: 0x1F6AE8))
            .padding(.top, 18)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
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
                .fill(LinearGradient(colors: [Color(hex: 0x1B1B22), Color(hex: 0x3A3A48)], startPoint: .top, endPoint: .bottom))
                .frame(width: 12, height: hang.strap)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0xE3E5EC), Color(hex: 0xB9BDCA)], startPoint: .top, endPoint: .bottom))
                .frame(width: 20, height: 14)
            BadgeCard(bot: hang.bot, sheen: sheen)
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
                if value.translation == .zero { Haptics.light() }
                lastAngle = next
                lastTime = now
                onDrag(next, velocity)
            }
            .onEnded { _ in
                Haptics.tick()
                onRelease()
            }
    }
}
