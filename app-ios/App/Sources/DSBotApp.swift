import SwiftUI

@main
struct DSBotApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ZStack {
                Aurora(seed: model.screen == .welcome ? 0 : 1.7)
                    .ignoresSafeArea()
                switch model.screen {
                case .welcome:
                    WelcomeView(
                        onPair: { model.go(.pair) },
                        onDemo: { model.startDemo() }
                    )
                    .transition(.blurReplace)
                case .pair:
                    PairView(model: model)
                        .transition(.blurReplace)
                case .home:
                    HomeView(model: model, team: model.team)
                        .transition(.blurReplace)
                }
            }
            .preferredColorScheme(.light)
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    /// The same color, darker (`amount` below 1) or mixed toward white (`lift` above 0).
    static func shade(_ hex: UInt32, amount: Double = 1, lift: Double = 0) -> Color {
        func channel(_ shift: UInt32) -> Double {
            let value = Double((hex >> shift) & 0xFF) / 255 * amount
            return min(1, value + (1 - value) * lift)
        }
        return Color(red: channel(16), green: channel(8), blue: channel(0))
    }
}
