import UIKit
import CoreHaptics

enum Haptics {
    private static let mediumGen = UIImpactFeedbackGenerator(style: .medium)
    private static let heavyGen = UIImpactFeedbackGenerator(style: .heavy)
    private static let rigidGen = UIImpactFeedbackGenerator(style: .rigid)
    private static var engine: CHHapticEngine?

    static func prepare() {
        mediumGen.prepare()
        heavyGen.prepare()
        rigidGen.prepare()
        startEngine()
    }

    private static func startEngine() {
        guard engine == nil, CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            let made = try CHHapticEngine()
            made.isAutoShutdownEnabled = true
            made.resetHandler = { try? Haptics.engine?.start() }
            try made.start()
            engine = made
        } catch {
            engine = nil
        }
    }

    /// A tap on a button.
    static func light() { mediumGen.impactOccurred(intensity: 0.8) }

    /// Taking hold of something.
    static func grab() { mediumGen.impactOccurred(intensity: 1.0) }

    /// One notch of travel; `strength` in 0...1.
    static func tick(_ strength: CGFloat = 0.7) { rigidGen.impactOccurred(intensity: max(0.3, min(1, strength))) }

    /// Something locking into place.
    static func lock() { heavyGen.impactOccurred(intensity: 1.0) }

    /// The stamp landing: a deep hit, a short rumble under it, then a sharper bounce.
    static func thud() {
        guard let engine else { fallbackThud(); return }
        func p(_ id: CHHapticEvent.ParameterID, _ value: Float) -> CHHapticEventParameter {
            CHHapticEventParameter(parameterID: id, value: value)
        }
        let events = [
            CHHapticEvent(eventType: .hapticTransient, parameters: [p(.hapticIntensity, 1.0), p(.hapticSharpness, 0.25)], relativeTime: 0),
            CHHapticEvent(eventType: .hapticContinuous, parameters: [p(.hapticIntensity, 0.85), p(.hapticSharpness, 0.1)], relativeTime: 0, duration: 0.14),
            CHHapticEvent(eventType: .hapticTransient, parameters: [p(.hapticIntensity, 0.8), p(.hapticSharpness, 0.65)], relativeTime: 0.12),
        ]
        do {
            try engine.start()
            let player = try engine.makePlayer(with: CHHapticPattern(events: events, parameters: []))
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            fallbackThud()
        }
    }

    private static func fallbackThud() {
        heavyGen.impactOccurred(intensity: 1.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { rigidGen.impactOccurred(intensity: 1.0) }
    }
}
