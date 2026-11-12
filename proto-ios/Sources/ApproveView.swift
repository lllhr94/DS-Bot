import SwiftUI

struct ApproveView: View {
    var onBack: () -> Void

    @State private var stamped = false
    /// 0...1: how far the stamp is pressing the slip down.
    @State private var press: CGFloat = 0
    @State private var slide: CGFloat = 0
    @State private var lastTick = 0
    @State private var shown = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    Haptics.light()
                    onBack()
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
                SlipShape()
                    .fill(.white)
                    .frame(width: 300, height: 330)
                    .rotationEffect(.degrees(5))
                    .offset(x: 14, y: 12)
                    .blur(radius: 1.5)
                    .opacity(0.8)
                    .shadow(color: Color(hex: 0x141432).opacity(0.10), radius: 14, y: 14)
                slip
                    .scaleEffect(1 - 0.02 * press)
                    .rotationEffect(.degrees(-4 - 1.4 * press))
                    .offset(y: 8 * press)
            }
            .scaleEffect(shown ? 1 : 0.9)
            .opacity(shown ? 1 : 0)
            .blur(radius: shown ? 0 : 10)

            Spacer(minLength: 12)

            VStack(spacing: 10) {
                Text(stamped ? "盖章，放行" : "运维在等你点头")
                    .font(.system(size: 30, weight: .heavy))
                    .tracking(-0.5)
                    .foregroundStyle(Color(hex: 0x0B0B0F))
                    .contentTransition(.opacity)
                Text(stamped ? "运维已经继续干活，做完会告诉你。" : "向右滑到底，就算批准。")
                    .font(.system(size: 17))
                    .foregroundStyle(Color(hex: 0x2A2A33))
                    .contentTransition(.opacity)
                Group {
                    if stamped {
                        Button {
                            reset()
                        } label: {
                            Text("再来一次")
                                .font(.system(size: 18, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 36)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.capsule)
                        .controlSize(.large)
                        .transition(.blurReplace)
                    } else {
                        SlideTrack(progress: $slide, onTick: tick, onDone: approve)
                            .transition(.blurReplace)
                    }
                }
                .padding(.top, 18)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .onAppear {
            Haptics.prepare()
            withAnimation(.spring(response: 0.6, dampingFraction: 0.72).delay(0.1)) { shown = true }
        }
    }

    private var slip: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("审 批 单")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(2)
                Spacer()
                Text("15:07").font(.system(size: 12, design: .monospaced))
            }
            .foregroundStyle(Color(hex: 0x4A4A55))

            HStack(spacing: 12) {
                Face(color: Bot.ops.light, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text("申请人").font(.system(size: 13)).foregroundStyle(Color(hex: 0x4A4A55))
                    Text("运维").font(.system(size: 20, weight: .heavy))
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("想做的事").font(.system(size: 13)).foregroundStyle(Color(hex: 0x4A4A55))
                Text("重启一个服务").font(.system(size: 17, weight: .semibold))
                Text("systemctl restart nginx")
                    .font(.system(size: 13, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(hex: 0xF1F0F6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            Line()
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
            Stamp()
                .scaleEffect(stamped ? 1 : 2.8)
                .opacity(stamped ? 1 : 0)
                .rotationEffect(.degrees(-14))
                .padding(.trailing, 16)
                .padding(.bottom, 14)
        }
        .shadow(color: Color(hex: 0x141432).opacity(0.18 - 0.06 * Double(press)), radius: 24 - 10 * press, y: 24 - 12 * press)
    }

    private func tick(_ step: Int) {
        if step != lastTick {
            lastTick = step
            Haptics.tick()
        }
    }

    private func approve() {
        // The stamp falls, lands with a thud, and the slip gives under it.
        withAnimation(.spring(response: 0.24, dampingFraction: 0.62)) { stamped = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.11) {
            Haptics.heavy()
            withAnimation(.spring(response: 0.1, dampingFraction: 0.7)) { press = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) {
                Haptics.rigid()
                withAnimation(.spring(response: 0.55, dampingFraction: 0.38)) { press = 0 }
            }
        }
    }

    private func reset() {
        Haptics.light()
        lastTick = 0
        withAnimation(.smooth(duration: 0.35)) {
            stamped = false
            slide = 0
        }
    }
}

/// The round seal.
private struct Stamp: View {
    private let ink = Color(hex: 0xC4222F)

    var body: some View {
        ZStack {
            Circle().strokeBorder(ink, lineWidth: 4)
            Circle().strokeBorder(ink, lineWidth: 1.5).padding(7)
            VStack(spacing: 2) {
                Text("已批准")
                    .font(.system(size: 24, weight: .black))
                    .tracking(2)
                Text("11-12 15:07")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
            }
            .foregroundStyle(ink)
        }
        .frame(width: 108, height: 108)
        .opacity(0.92)
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
            let travel = proxy.size.width - knob - 10
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
                                    withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) { progress = 1 }
                                    onDone()
                                } else {
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

/// A paper slip: a perforated top edge and rounded bottom corners.
struct SlipShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let count = max(1, Int(rect.width / 18))
        let step = rect.width / CGFloat(count)
        let bite = step * 0.3
        let corner: CGFloat = 18
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        for index in 0..<count {
            let cx = rect.minX + (CGFloat(index) + 0.5) * step
            p.addLine(to: CGPoint(x: cx - bite, y: rect.minY))
            p.addArc(center: CGPoint(x: cx, y: rect.minY), radius: bite, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: true)
        }
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - corner))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - corner, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + corner, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - corner), control: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}
