import SwiftUI
import CoreMotion
import QuartzCore

/// Pendulum physics for the hanging badges. Angles are in radians; a positive
/// angle turns the badge clockwise about its pivot, which carries it to the left.
final class Sway: NSObject, ObservableObject {
    struct Bob {
        var angle: Double
        var velocity: Double
        let length: Double
        var held = false
    }

    @Published var bobs: [Bob]
    /// Where "down" is for the badges, from the phone's tilt.
    @Published var rest: Double = 0

    private let motion = CMMotionManager()
    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0

    init(lengths: [Double]) {
        bobs = lengths.enumerated().map { index, length in
            // Start swung out, so the badges settle as the screen appears.
            Bob(angle: index % 2 == 0 ? 0.32 : -0.28, velocity: 0, length: length)
        }
        super.init()
    }

    func start() {
        if motion.isDeviceMotionAvailable {
            motion.deviceMotionUpdateInterval = 1.0 / 60.0
            motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
                guard let self, let g = data?.gravity else { return }
                // Lying flat there is no "down" on the screen: hang straight.
                if hypot(g.x, g.y) < 0.25 { self.rest = 0; return }
                let angle = -atan2(g.x, -g.y)
                self.rest = max(-1.0, min(1.0, angle))
            }
        }
        last = 0
        let link = CADisplayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
        motion.stopDeviceMotionUpdates()
    }

    @objc private func step(_ link: CADisplayLink) {
        let now = link.timestamp
        let dt = last == 0 ? 1.0 / 60.0 : min(now - last, 1.0 / 30.0)
        last = now
        var next = bobs
        for index in next.indices where !next[index].held {
            // A shorter strap swings faster, as a real pendulum does.
            let stiffness = 24.0 * 200.0 / next[index].length
            let pull = -stiffness * sin(next[index].angle - rest)
            let drag = -1.1 * next[index].velocity
            next[index].velocity += (pull + drag) * dt
            next[index].angle += next[index].velocity * dt
        }
        bobs = next
    }

    func hold(_ index: Int, angle: Double, velocity: Double) {
        bobs[index].held = true
        bobs[index].angle = max(-1.2, min(1.2, angle))
        bobs[index].velocity = velocity
    }

    func release(_ index: Int) {
        bobs[index].held = false
        bobs[index].velocity = max(-9, min(9, bobs[index].velocity))
    }
}
