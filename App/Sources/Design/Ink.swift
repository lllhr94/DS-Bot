import SwiftUI
import UIKit

/// Clio's design system: every color, type size, space and corner comes from here.
enum Ink {
    private static func pair(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }

    // MARK: Colors

    static let paper = pair(0xF6F1E7, 0x1C1A17)
    static let paperRaised = pair(0xFBF8F1, 0x26231F)
    static let ink = pair(0x2B2A27, 0xECE6DA)
    static let inkSoft = pair(0x6F6A60, 0xA39C8E)
    static let inkFaint = pair(0xA8A294, 0x6E685D)
    static let rule = pair(0xE4DCCB, 0x37332D)
    static let accent = pair(0x4A6A8A, 0x8FB0CF)
    static let accentWash = pair(0xE3EAF0, 0x2A3642)
    static let mine = pair(0xECE4D3, 0x322E28)
    static let ok = pair(0x5E8C6A, 0x7FB08C)
    static let warn = pair(0xC08A3E, 0xD9A65C)
    static let stop = pair(0xB4534B, 0xD4776F)

    /// The washes a companion's portrait can sit on.
    static let washes: [Color] = [
        accentWash,
        pair(0xEFE3E0, 0x3A2E2C),
        pair(0xE3EADF, 0x2C352B),
        pair(0xF1E6D2, 0x3A3226),
    ]

    // MARK: Type

    /// Whether the system's Songti is there; the serif system face stands in when it is not.
    static let hasSongti = UIFont(name: "STSongti-SC-Regular", size: 17) != nil

    /// The reading face: titles, a companion's words, notes.
    static func serif(_ size: CGFloat, bold: Bool = false, relativeTo style: Font.TextStyle = .body) -> Font {
        if hasSongti {
            return .custom(bold ? "STSongti-SC-Bold" : "STSongti-SC-Regular", size: size, relativeTo: style)
        }
        return .system(size: size, weight: bold ? .bold : .regular, design: .serif)
    }

    static let display = serif(30, bold: true, relativeTo: .largeTitle)
    static let title = serif(22, bold: true, relativeTo: .title2)
    static let reading = serif(17, relativeTo: .body)
    static let readingBold = serif(17, bold: true, relativeTo: .body)
    static let label = Font.system(size: 16, weight: .medium)
    static let secondary = Font.system(size: 14)
    static let footnote = Font.system(size: 12)
    static let code = Font.system(size: 14, design: .monospaced)

    /// The space between the lines of reading text.
    static let leading: CGFloat = 8

    // MARK: Space and corners

    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        static let huge: CGFloat = 48
        /// The page's side margin.
        static let page: CGFloat = 20
    }

    enum Radius {
        static let small: CGFloat = 8
        static let card: CGFloat = 14
        static let sheet: CGFloat = 22
    }

    // MARK: Motion

    enum Motion {
        static let press = Animation.spring(response: 0.25, dampingFraction: 0.7)
        static let unfold = Animation.spring(response: 0.42, dampingFraction: 0.82)
        static let settle = Animation.smooth(duration: 0.35)
    }
}

/// Anything tappable: gives a little under the finger, springs back, and ticks.
struct PressStyle: ButtonStyle {
    var haptic = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(Ink.Motion.press, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed, haptic { Haptics.tick(0.5) }
            }
    }
}

extension View {
    /// A card that reads as paper: a raised sheet with a hairline edge.
    func paperCard(radius: CGFloat = Ink.Radius.card) -> some View {
        background(Ink.paperRaised, in: .rect(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Ink.rule, lineWidth: 1))
            .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
    }

    /// A small glass capsule: only for controls that float above content.
    func glassChip() -> some View {
        padding(.horizontal, Ink.Space.m)
            .frame(height: 38)
            .glassEffect(.regular, in: .capsule)
    }
}

/// Lets a text out glyph by glyph, each one fading in.
struct FadeIn: TextRenderer {
    /// How many glyphs are on their way out; the last `ramp` of them are still fading.
    var shown: Double
    var ramp: Double = 10

    var animatableData: Double {
        get { shown }
        set { shown = newValue }
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        var index = 0.0
        for line in layout {
            for run in line {
                for slice in run {
                    let alpha = min(1, max(0, (shown - index) / ramp))
                    if alpha > 0 {
                        var soft = context
                        soft.opacity = alpha
                        soft.draw(slice)
                    }
                    index += 1
                }
            }
        }
    }
}
