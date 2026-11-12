import SwiftUI

@main
struct BotProtoApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    @State private var page = 0

    var body: some View {
        ZStack {
            Aurora(seed: page == 0 ? 0 : 1.7)
                .ignoresSafeArea()
            if page == 0 {
                WelcomeView { withAnimation(.smooth(duration: 0.55)) { page = 1 } }
                    .transition(.blurReplace)
            } else {
                ApproveView { withAnimation(.smooth(duration: 0.55)) { page = 0 } }
                    .transition(.blurReplace)
            }
        }
        .preferredColorScheme(.light)
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
}
