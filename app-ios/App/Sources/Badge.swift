import SwiftUI

/// How one work badge looks.
struct BadgeLook: Equatable {
    var name: String
    var role: String
    var status: String
    var light: Color
    /// The Bot's color as 0xRRGGBB.
    var tone: UInt32

    static let tones: [String: UInt32] = [
        "black": 0x3C4048, "brown": 0x8D6E57, "red": 0xE5484D, "orange": 0xF76B15, "yellow": 0xD4A017,
        "green": 0x30A46C, "cyan": 0x12A5B4, "blue": 0x4F7DF3, "violet": 0x7D5AFF, "magenta": 0xD3458B,
        "gray": 0x8B8F98, "aurora": 0x5CC8A0,
    ]

    static func tone(named name: String?) -> UInt32 { tones[name ?? ""] ?? 0x4F7DF3 }

    var dark: Color { .shade(tone, amount: 0.62) }
    var mid: Color { .shade(tone, amount: 0.84) }
    var face: Color { .shade(tone, amount: 0.95, lift: 0.28) }
}

/// A Bot's round face mark.
struct Face: View {
    let color: Color
    var size: CGFloat = 66

    var body: some View {
        ZStack {
            Circle().fill(color)
            Ellipse()
                .fill(Color.white.opacity(0.25))
                .frame(width: size * 0.55, height: size * 0.3)
                .offset(x: -size * 0.14, y: -size * 0.25)
            HStack(spacing: size * 0.14) {
                Circle().fill(.white).frame(width: size * 0.14, height: size * 0.14)
                Circle().fill(.white).frame(width: size * 0.14, height: size * 0.14)
            }
            Smile()
                .stroke(.white, style: StrokeStyle(lineWidth: size * 0.05, lineCap: .round))
                .frame(width: size * 0.24, height: size * 0.07)
                .offset(y: size * 0.2)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
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

/// The work badge of one Bot. `sheen` in -1...1 moves the light band across it.
struct BadgeCard: View {
    let look: BadgeLook
    var sheen: Double = 0

    var body: some View {
        VStack(spacing: 8) {
            Capsule().fill(Color.black.opacity(0.3)).frame(width: 36, height: 8)
            Face(color: look.face).padding(.top, 6)
            Text(look.name)
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(look.role)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.95))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Circle().fill(look.light).frame(width: 7, height: 7)
                Text(look.status).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 26)
            .background(Color.black.opacity(0.22), in: Capsule())
        }
        .padding(12)
        .frame(width: 150, height: 204)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(colors: [look.dark, look.mid], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.30 + sheen * 0.25),
                            .init(color: .white.opacity(0.28), location: 0.46 + sheen * 0.25),
                            .init(color: .clear, location: 0.62 + sheen * 0.25),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .allowsHitTesting(false)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
        }
        .shadow(color: look.dark.opacity(0.35), radius: 18, x: 0, y: 18)
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
