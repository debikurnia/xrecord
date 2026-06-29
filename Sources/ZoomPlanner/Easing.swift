import Foundation

/// Easing curves used to animate zoom scale and pan transitions.
public enum Easing {
    /// Smooth S-curve: slow start, fast middle, slow end. Input is clamped to [0, 1].
    public static func easeInOutCubic(_ x: Double) -> Double {
        let p = min(max(x, 0), 1)
        if p < 0.5 {
            return 4 * p * p * p
        }
        let f = -2 * p + 2
        return 1 - (f * f * f) / 2
    }
}
