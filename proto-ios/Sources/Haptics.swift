import UIKit

enum Haptics {
    private static let lightGen = UIImpactFeedbackGenerator(style: .light)
    private static let heavyGen = UIImpactFeedbackGenerator(style: .heavy)
    private static let rigidGen = UIImpactFeedbackGenerator(style: .rigid)
    private static let tickGen = UISelectionFeedbackGenerator()
    private static let noteGen = UINotificationFeedbackGenerator()

    static func prepare() {
        lightGen.prepare()
        heavyGen.prepare()
        rigidGen.prepare()
        tickGen.prepare()
    }
    static func light() { lightGen.impactOccurred() }
    static func heavy() { heavyGen.impactOccurred(intensity: 1.0) }
    static func rigid() { rigidGen.impactOccurred(intensity: 0.9) }
    static func tick() { tickGen.selectionChanged() }
    static func success() { noteGen.notificationOccurred(.success) }
}
