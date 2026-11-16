import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    enum Screen { case welcome, setup, home }

    @Published private(set) var screen: Screen
    let team = TeamModel()

    init() {
        screen = team.phase == .setup ? .welcome : .home
    }

    func go(_ next: Screen) {
        withAnimation(.smooth(duration: 0.5)) { screen = next }
    }

    func startDemo() {
        team.showDemo()
        go(.home)
    }

    /// Leaves the demo: back to the real team, or to setting one up.
    func leave() {
        team.leaveDemo()
        go(team.phase == .setup ? .setup : .home)
    }
}
