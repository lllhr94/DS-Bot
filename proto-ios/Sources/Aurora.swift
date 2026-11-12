import SwiftUI

/// The soft moving backdrop: a 3x3 mesh whose inner points drift slowly.
struct Aurora: View {
    var seed: Double

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate * 0.12 + seed
            let a = Float(sin(t)) * 0.08
            let b = Float(cos(t * 0.8)) * 0.08
            let c = Float(sin(t * 1.3)) * 0.06
            MeshGradient(
                width: 3,
                height: 3,
                points: [
                    SIMD2<Float>(0, 0), SIMD2<Float>(0.5 + a, 0), SIMD2<Float>(1, 0),
                    SIMD2<Float>(0, 0.45 + b), SIMD2<Float>(0.5 + c, 0.5 + a), SIMD2<Float>(1, 0.55 - b),
                    SIMD2<Float>(0, 1), SIMD2<Float>(0.5 - a, 1), SIMD2<Float>(1, 1),
                ],
                colors: [
                    Color(hex: 0xFFD3DE), Color(hex: 0xF2F0FA), Color(hex: 0xCFE2FF),
                    Color(hex: 0xF4F2FA), Color(hex: 0xF7F5FB), Color(hex: 0xFFE6CF),
                    Color(hex: 0xD2F1E6), Color(hex: 0xF5F3FA), Color(hex: 0xF3ECFA),
                ]
            )
        }
    }
}
