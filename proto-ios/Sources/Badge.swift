import SwiftUI

struct Bot: Identifiable {
    let id: Int
    let name: String
    let role: String
    let status: String
    let dot: Color
    let dark: Color
    let light: Color
    let face: Color

    static let chief = Bot(id: 0, name: "主管", role: "分派任务 · 管理团队", status: "随时待命",
                           dot: Color(hex: 0x7CF0B8), dark: Color(hex: 0x3442C8), light: Color(hex: 0x5563E6), face: Color(hex: 0x8792F5))
    static let scout = Bot(id: 1, name: "调研", role: "查资料 · 逛网页", status: "正在干活",
                           dot: Color(hex: 0xFFD98A), dark: Color(hex: 0x9E2E60), light: Color(hex: 0xC2417A), face: Color(hex: 0xE57AA8))
    static let ops = Bot(id: 2, name: "运维", role: "看服务 · 跑命令", status: "等你批准",
                         dot: Color(hex: 0xFFD98A), dark: Color(hex: 0x0A6F63), light: Color(hex: 0x0C8172), face: Color(hex: 0x2BB3A1))
    static let writer = Bot(id: 3, name: "写手", role: "写文档 · 改稿子", status: "空闲",
                            dot: Color(hex: 0x7CF0B8), dark: Color(hex: 0x8E4A08), light: Color(hex: 0xB5600F), face: Color(hex: 0xD98A3A))
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
    let bot: Bot
    var sheen: Double = 0

    var body: some View {
        VStack(spacing: 8) {
            Capsule().fill(Color.black.opacity(0.3)).frame(width: 36, height: 8)
            Face(color: bot.face).padding(.top, 6)
            Text(bot.name)
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(.white)
            Text(bot.role)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.95))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Circle().fill(bot.dot).frame(width: 7, height: 7)
                Text(bot.status).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 26)
            .background(Color.black.opacity(0.22), in: Capsule())
        }
        .padding(12)
        .frame(width: 150, height: 204)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(colors: [bot.dark, bot.light], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay {
            // The light band: it slides as the phone tilts.
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
        .shadow(color: bot.dark.opacity(0.35), radius: 18, x: 0, y: 18)
    }
}
