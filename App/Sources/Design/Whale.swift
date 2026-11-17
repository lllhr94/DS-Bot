import SwiftUI

/// Clio's own whale: a round silhouette drawn here, in three candidate outlines.
struct WhaleLook: Equatable {
    /// Where the body begins at the tail end, 0...1 across.
    var start: CGFloat
    /// The body's middle line, 0...1 down.
    var mid: CGFloat
    /// How high the back rises (smaller is higher).
    var back: CGFloat
    /// How deep the belly hangs.
    var belly: CGFloat
    /// Where the flukes part.
    var root: CGPoint
    /// The length of each fluke.
    var fluke: CGFloat
    /// The direction of each fluke, in degrees.
    var lobes: [Double]
    var fin: CGPoint
    var eye: CGPoint

    static let looks: [WhaleLook] = [
        WhaleLook(start: 0.26, mid: 0.57, back: 0.16, belly: 0.96, root: CGPoint(x: 0.17, y: 0.33), fluke: 0.17, lobes: [-150, -55], fin: CGPoint(x: 0.60, y: 0.845), eye: CGPoint(x: 0.80, y: 0.53)),
        WhaleLook(start: 0.20, mid: 0.58, back: 0.28, belly: 0.88, root: CGPoint(x: 0.13, y: 0.34), fluke: 0.20, lobes: [-160, -60], fin: CGPoint(x: 0.58, y: 0.80), eye: CGPoint(x: 0.80, y: 0.55)),
        WhaleLook(start: 0.27, mid: 0.60, back: 0.16, belly: 0.86, root: CGPoint(x: 0.19, y: 0.36), fluke: 0.14, lobes: [-145, -50], fin: CGPoint(x: 0.62, y: 0.80), eye: CGPoint(x: 0.79, y: 0.55)),
    ]

    static let names = ["团子", "长调", "墩墩"]
}

/// The body: one fat curve over the back, round the head and under the belly, with a small fin.
struct WhaleBody: Shape {
    var look: WhaleLook

    func path(in rect: CGRect) -> Path {
        func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        var path = Path()
        let start = look.start, mid = look.mid
        path.move(to: at(start, mid))
        path.addCurve(to: at(0.96, mid), control1: at(start + 0.02, look.back), control2: at(0.93, look.back - 0.02))
        path.addCurve(to: at(start, mid), control1: at(0.98, look.belly), control2: at(start + 0.06, look.belly))
        path.closeSubpath()
        let turn: CGFloat = 0.45
        var fin = Path()
        for step in 0..<48 {
            let angle = 2 * CGFloat.pi * CGFloat(step) / 48
            let x = 0.09 * cos(angle), y = 0.04 * sin(angle)
            let point = at(look.fin.x + x * cos(turn) - y * sin(turn), look.fin.y + x * sin(turn) + y * cos(turn))
            if step == 0 { fin.move(to: point) } else { fin.addLine(to: point) }
        }
        fin.closeSubpath()
        path.addPath(fin)
        return path
    }
}

/// The tail: a stem and two leaf-shaped flukes. Kept apart from the body so it can wag.
struct WhaleTail: Shape {
    var look: WhaleLook

    func path(in rect: CGRect) -> Path {
        func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        let root = look.root, start = look.start, mid = look.mid
        var path = Path()
        path.move(to: at(root.x - 0.035, root.y + 0.02))
        path.addQuadCurve(to: at(start + 0.12, mid + 0.10), control: at(root.x - 0.03, mid + 0.02))
        path.addLine(to: at(start + 0.16, mid - 0.14))
        path.addQuadCurve(to: at(root.x + 0.035, root.y + 0.01), control: at(root.x + 0.06, root.y + 0.12))
        path.closeSubpath()
        for degrees in look.lobes {
            let turn = CGFloat(degrees) * .pi / 180
            var lobe = Path()
            for step in 0..<60 {
                let angle = 2 * CGFloat.pi * CGFloat(step) / 60
                let x = look.fluke / 2 + look.fluke / 2 * cos(angle)
                // Pinched at the root, so each fluke reads as a leaf.
                let along = min(1, max(0, x / look.fluke))
                let y = look.fluke * 0.25 * sin(angle) * (0.35 + 0.65 * pow(sin(.pi * along), 0.6))
                let point = at(root.x + x * cos(turn) - y * sin(turn), root.y + x * sin(turn) + y * cos(turn))
                if step == 0 { lobe.move(to: point) } else { lobe.addLine(to: point) }
            }
            lobe.closeSubpath()
            path.addPath(lobe)
        }
        return path
    }
}

/// What the whale is doing.
enum WhalePose: String, CaseIterable {
    /// 闲坐
    case idle
    /// 沉吟
    case thinking
    /// 落笔
    case writing
    /// 候印
    case waiting

    var word: String {
        switch self {
        case .idle: "闲坐"
        case .thinking: "沉吟"
        case .writing: "落笔"
        case .waiting: "候印"
        }
    }
}

/// The whale in its round frame: a companion's portrait, and the small mascot by the composer.
struct Whale: View {
    var size: CGFloat = 44
    var pose: WhalePose = .idle
    var wash: Color = Ink.accentWash
    var tone: Color = Ink.accent
    /// Which outline; nil follows the one the user picked.
    var look: Int?
    /// Portraits in lists hold still.
    var still = false

    @AppStorage("whale.look") private var picked = 0
    @Environment(\.accessibilityReduceMotion) private var calm

    private var outline: WhaleLook {
        let index = look ?? picked
        return WhaleLook.looks[min(max(index, 0), WhaleLook.looks.count - 1)]
    }

    var body: some View {
        if still || calm {
            figure(at: 0)
        } else {
            TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
                figure(at: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
    }

    private func figure(at time: Double) -> some View {
        let bob = pose == .writing ? sin(time * 5) * 0.012 : sin(time * 1.4) * 0.02
        let wag: Double = switch pose {
        case .writing: sin(time * 9) * 10
        case .waiting: sin(time * 3) * 6
        default: sin(time * 1.4) * 3
        }
        let inner = size * 0.78
        return ZStack {
            Circle().fill(wash)
            ZStack {
                WhaleTail(look: outline)
                    .fill(tone)
                    .rotationEffect(.degrees(wag), anchor: UnitPoint(x: outline.start + 0.1, y: outline.mid))
                WhaleBody(look: outline).fill(tone)
                // The eye: a dot of the wash, so it stays a silhouette.
                Circle()
                    .fill(wash)
                    .frame(width: inner * 0.058, height: inner * 0.058)
                    .position(x: inner * outline.eye.x, y: inner * outline.eye.y)
                if pose == .thinking { bubbles(time, inner) }
                if pose == .waiting { spout(time, inner) }
            }
            .frame(width: inner, height: inner)
            .offset(x: -size * 0.01, y: size * (0.04 + bob))
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private func bubbles(_ time: Double, _ inner: CGFloat) -> some View {
        ForEach(0..<3, id: \.self) { index in
            let phase = (time * 0.7 + Double(index) / 3).truncatingRemainder(dividingBy: 1)
            Circle()
                .fill(tone.opacity(0.75 * (1 - phase)))
                .frame(width: inner * (0.05 + 0.03 * CGFloat(index)), height: inner * (0.05 + 0.03 * CGFloat(index)))
                .position(x: inner * (0.74 + 0.07 * CGFloat(index)), y: inner * (0.24 - 0.2 * phase))
        }
    }

    private func spout(_ time: Double, _ inner: CGFloat) -> some View {
        let rise = (sin(time * 3) + 1) / 2
        return ForEach([-1.0, 1.0], id: \.self) { side in
            Capsule()
                .fill(tone)
                .frame(width: inner * 0.035, height: inner * (0.08 + 0.07 * rise))
                .rotationEffect(.degrees(side * 22))
                .position(x: inner * (0.66 + 0.035 * side), y: inner * (0.13 - 0.03 * rise))
        }
    }
}
