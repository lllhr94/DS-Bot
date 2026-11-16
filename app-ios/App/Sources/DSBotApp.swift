import SwiftUI
import UserNotifications

/// Shows a Bot's notification even while the app is open.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}

@main
struct DSBotApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ZStack {
                Aurora(seed: model.screen == .welcome ? 0 : 1.7)
                    .ignoresSafeArea()
                switch model.screen {
                case .welcome:
                    WelcomeView(
                        onStart: { model.go(.setup) },
                        onDemo: { model.startDemo() }
                    )
                    .transition(.blurReplace)
                case .setup:
                    SetupView(team: model.team, first: true) { model.go(.home) }
                        .transition(.blurReplace)
                case .home:
                    HomeView(model: model, team: model.team)
                        .transition(.blurReplace)
                }
            }
            .preferredColorScheme(.light)
            .fontDesign(.rounded)
            .onChange(of: scenePhase) {
                if scenePhase == .active { model.team.wake() }
            }
            .task {
                // Messages set for later land in their chats while the app is open too.
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 20_000_000_000)
                    model.team.deliverDue()
                }
            }
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
