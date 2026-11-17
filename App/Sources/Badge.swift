import SwiftUI

/// What a Bot's face is feeling.
enum Mood: Equatable {
    case happy, busy, asking, sleepy

    static func of(_ status: String) -> Mood {
        if status.contains("等你") || status.contains("需要") { return .asking }
        if status.contains("干活") { return .busy }
        return .happy
    }
}

/// The ears a Bot wears. The same name always gets the same ears.
enum Ears: CaseIterable, Equatable {
    case bear, cat, bunny, sprout

    static func of(_ name: String) -> Ears {
        let sum = name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return allCases[sum % allCases.count]
    }
}

/// How one work badge looks.
struct BadgeLook: Equatable {
    var name: String
    var role: String
    var status: String
    var light: Color
    /// The Bot's color as 0xRRGGBB.
    var tone: UInt32
    var mood: Mood = .happy

    static let tones: [String: UInt32] = [
        "black": 0x3C4048, "brown": 0x8D6E57, "red": 0xE5484D, "orange": 0xF76B15, "yellow": 0xD4A017,
        "green": 0x30A46C, "cyan": 0x12A5B4, "blue": 0x4F7DF3, "violet": 0x7D5AFF, "magenta": 0xD3458B,
        "gray": 0x8B8F98, "aurora": 0x5CC8A0,
    ]

    static func tone(named name: String?) -> UInt32 { tones[name ?? ""] ?? 0x4F7DF3 }

    var dark: Color { .shade(tone, amount: 0.62) }
    var mid: Color { .shade(tone, amount: 0.84) }
    /// Text and line work on the pale card.
    var ink: Color { .shade(tone, amount: 0.42) }
    var paleTop: Color { .shade(tone, lift: 0.80) }
    var paleBottom: Color { .shade(tone, lift: 0.58) }
}

/// A Bot's face: a round head with ears, blush, and eyes that blink.
struct Face: View {
    let tone: UInt32
    var size: CGFloat = 66
    var mood: Mood = .happy
    var ears: Ears = .bear

    @State private var blink = false

    private var skin: Color { .shade(tone, lift: 0.36) }
    private var skinLight: Color { .shade(tone, lift: 0.52) }
    private var inner: Color { Color(hex: 0xFFC2D1) }
    private var ink: Color { .shade(tone, amount: 0.30) }

    var body: some View {
        ZStack {
            earShapes
            Circle()
                .fill(LinearGradient(colors: [skinLight, skin], startPoint: .top, endPoint: .bottom))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: max(1.5, size * 0.04)))
            Ellipse()
                .fill(Color.white.opacity(0.45))
                .frame(width: size * 0.34, height: size * 0.16)
                .rotationEffect(.degrees(-24))
                .offset(x: -size * 0.2, y: -size * 0.3)
            // Blush.
            HStack(spacing: size * 0.42) {
                Ellipse().fill(Color(hex: 0xFF7E9D).opacity(0.5)).frame(width: size * 0.17, height: size * 0.10)
                Ellipse().fill(Color(hex: 0xFF7E9D).opacity(0.5)).frame(width: size * 0.17, height: size * 0.10)
            }
            .offset(y: size * 0.17)
            HStack(spacing: size * 0.22) {
                eye
                eye
            }
            .offset(y: mood == .busy ? size * 0.05 : size * 0.02)
            mouth.offset(y: size * 0.2)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .task {
            // A blink every few seconds, each face on its own beat.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64.random(in: 2_400_000_000...5_200_000_000))
                withAnimation(.easeIn(duration: 0.07)) { blink = true }
                try? await Task.sleep(nanoseconds: 120_000_000)
                withAnimation(.easeOut(duration: 0.1)) { blink = false }
            }
        }
    }

    @ViewBuilder
    private var eye: some View {
        if mood == .sleepy {
            Smile()
                .stroke(ink, style: StrokeStyle(lineWidth: size * 0.04, lineCap: .round))
                .frame(width: size * 0.13, height: size * 0.04)
        } else {
            let big: CGFloat = mood == .asking ? 1.18 : 1
            Capsule()
                .fill(ink)
                .frame(width: size * 0.115 * big, height: size * 0.165 * big)
                .overlay(alignment: .topLeading) {
                    Circle()
                        .fill(.white)
                        .frame(width: size * 0.05, height: size * 0.05)
                        .offset(x: size * 0.012, y: size * 0.02)
                }
                .scaleEffect(x: 1, y: blink ? 0.12 : 1)
        }
    }

    @ViewBuilder
    private var mouth: some View {
        switch mood {
        case .happy:
            Smile()
                .stroke(ink, style: StrokeStyle(lineWidth: size * 0.04, lineCap: .round))
                .frame(width: size * 0.15, height: size * 0.05)
        case .busy:
            Capsule().fill(ink).frame(width: size * 0.1, height: size * 0.035)
        case .asking:
            Ellipse().fill(ink).frame(width: size * 0.08, height: size * 0.1)
        case .sleepy:
            Circle().fill(ink).frame(width: size * 0.055, height: size * 0.055)
        }
    }

    @ViewBuilder
    private var earShapes: some View {
        switch ears {
        case .bear:
            ForEach([-1.0, 1.0], id: \.self) { side in
                Circle()
                    .fill(skin)
                    .overlay(Circle().fill(inner).padding(size * 0.08))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: max(1.5, size * 0.04)))
                    .frame(width: size * 0.36, height: size * 0.36)
                    .offset(x: side * size * 0.34, y: -size * 0.36)
            }
        case .cat:
            ForEach([-1.0, 1.0], id: \.self) { side in
                EarTip()
                    .fill(skin)
                    .overlay(EarTip().fill(inner).scaleEffect(0.5, anchor: .bottom))
                    .frame(width: size * 0.36, height: size * 0.38)
                    .rotationEffect(.degrees(side * 22), anchor: .bottom)
                    .offset(x: side * size * 0.28, y: -size * 0.50)
            }
        case .bunny:
            ForEach([-1.0, 1.0], id: \.self) { side in
                Capsule()
                    .fill(skin)
                    .overlay(Capsule().fill(inner).padding(size * 0.055))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.9), lineWidth: max(1.5, size * 0.04)))
                    .frame(width: size * 0.22, height: size * 0.46)
                    .rotationEffect(.degrees(side * 10), anchor: .bottom)
                    .offset(x: side * size * 0.17, y: -size * 0.56)
            }
        case .sprout:
            ForEach([-1.0, 1.0], id: \.self) { side in
                Ellipse()
                    .fill(Color(hex: 0x6FD08C))
                    .overlay(Ellipse().strokeBorder(Color.white.opacity(0.9), lineWidth: max(1, size * 0.03)))
                    .frame(width: size * 0.28, height: size * 0.15)
                    .rotationEffect(.degrees(side * -28), anchor: side < 0 ? .trailing : .leading)
                    .offset(x: side * size * 0.14, y: -size * 0.55)
            }
        }
    }
}

private struct Smile: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.midX, y: rect.maxY * 2))
        return p
    }
}

/// A cat ear: a triangle with a soft tip.
private struct EarTip: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.midX - rect.width * 0.08, y: rect.minY + rect.height * 0.08), control: CGPoint(x: rect.minX + rect.width * 0.2, y: rect.midY))
        p.addQuadCurve(to: CGPoint(x: rect.midX + rect.width * 0.08, y: rect.minY + rect.height * 0.08), control: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.04))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY), control: CGPoint(x: rect.maxX - rect.width * 0.2, y: rect.midY))
        p.closeSubpath()
        return p
    }
}

/// The work badge of one Bot: a pale candy card with a white sticker edge. `sheen` in -1...1 moves the light band across it.
struct BadgeCard: View {
    let look: BadgeLook
    var sheen: Double = 0

    static let corner: CGFloat = 30

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
        VStack(spacing: 5) {
            Capsule()
                .fill(Color.white.opacity(0.95))
                .overlay(Capsule().strokeBorder(look.ink.opacity(0.12), lineWidth: 1))
                .frame(width: 34, height: 9)
            Face(tone: look.tone, size: 68, mood: look.mood, ears: Ears.of(look.name))
                .padding(.top, 24)
                .padding(.bottom, 2)
            Text(look.name)
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(look.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(look.role)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(look.ink.opacity(0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Circle().fill(look.light).frame(width: 8, height: 8)
                Text(look.status)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(look.ink)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 26)
            .background(Color.white.opacity(0.82), in: Capsule())
        }
        .padding(12)
        .frame(width: 150, height: 204)
        .background {
            // The shadow sits on the plain shape, which is far cheaper to move than a shadow of the whole card.
            shape
                .fill(LinearGradient(colors: [look.paleTop, look.paleBottom], startPoint: .top, endPoint: .bottom))
                .shadow(color: look.dark.opacity(0.28), radius: 14, x: 0, y: 14)
        }
        .overlay(alignment: .topTrailing) {
            Image(systemName: "sparkle")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .rotationEffect(.degrees(14))
                .padding(.top, 30)
                .padding(.trailing, 16)
        }
        .overlay(alignment: .topLeading) {
            Image(systemName: "sparkle")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.top, 46)
                .padding(.leading, 20)
        }
        .overlay {
            shape
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.30 + sheen * 0.25),
                            .init(color: .white.opacity(0.38), location: 0.46 + sheen * 0.25),
                            .init(color: .clear, location: 0.62 + sheen * 0.25),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .allowsHitTesting(false)
        }
        .overlay { shape.strokeBorder(Color.white, lineWidth: 3) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(look.name)，\(look.status)")
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
