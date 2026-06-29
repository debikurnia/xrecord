import Foundation
import ProjectModel

/// A smoothed cursor track that can be queried at any time.
public struct SmoothedCursor: Sendable {
    /// Time-sorted samples.
    public let samples: [CursorSample]

    public init(samples: [CursorSample]) {
        self.samples = samples.sorted { $0.t < $1.t }
    }

    /// The interpolated cursor position at time `t`, or nil if the track is empty.
    /// Clamps to the first/last position outside the sampled range.
    public func position(at t: Double) -> Point? {
        guard let first = samples.first, let last = samples.last else { return nil }
        if t <= first.t { return first.position }
        if t >= last.t { return last.position }

        // Binary search for the bracketing pair.
        var lo = 0
        var hi = samples.count - 1
        while lo + 1 < hi {
            let mid = (lo + hi) / 2
            if samples[mid].t <= t { lo = mid } else { hi = mid }
        }
        let a = samples[lo]
        let b = samples[hi]
        let span = b.t - a.t
        let f = span > 0 ? (t - a.t) / span : 0
        return lerp(a.position, b.position, f)
    }
}

/// Zero-phase Gaussian smoothing of a cursor track. Because rendering is
/// offline, smoothing is centered (no lag): each output position is a
/// time-weighted average of nearby samples, turning shaky motion into a glide.
public struct CursorSmoother: Sendable {
    /// Standard deviation of the Gaussian window, in seconds.
    public var sigma: Double

    public init(sigma: Double = 0.08) {
        self.sigma = sigma
    }

    public func smooth(_ samples: [CursorSample]) -> [CursorSample] {
        guard sigma > 0, samples.count > 2 else { return samples }

        let sorted = samples.sorted { $0.t < $1.t }
        let window = 3 * sigma          // truncate the kernel beyond 3σ
        let twoSigmaSquared = 2 * sigma * sigma

        var result: [CursorSample] = []
        result.reserveCapacity(sorted.count)

        var windowStart = 0
        for i in 0..<sorted.count {
            let ti = sorted[i].t
            while sorted[windowStart].t < ti - window { windowStart += 1 }

            var weightSum = 0.0
            var xSum = 0.0
            var ySum = 0.0
            var j = windowStart
            while j < sorted.count, sorted[j].t <= ti + window {
                let dt = sorted[j].t - ti
                let w = exp(-(dt * dt) / twoSigmaSquared)
                weightSum += w
                xSum += w * sorted[j].position.x
                ySum += w * sorted[j].position.y
                j += 1
            }

            let position = weightSum > 0
                ? Point(x: xSum / weightSum, y: ySum / weightSum)
                : sorted[i].position
            result.append(CursorSample(t: ti, position: position))
        }

        return result
    }
}

/// Opacity of the drawn cursor at time `t`, emulating macOS: the cursor is fully
/// visible while there is recent activity, fades out after `idleDelay` seconds of
/// no activity, and pops back instantly when activity resumes.
///
/// `activityTimes` must be sorted ascending. It typically holds the timestamps of
/// cursor-movement samples plus clicks (movement only is recorded when the mouse
/// actually moves, so the gaps between samples mark idle periods).
public func cursorIdleAlpha(
    at t: Double,
    activityTimes: [Double],
    idleDelay: Double = 0.6,
    fadeDuration: Double = 0.35
) -> Double {
    guard !activityTimes.isEmpty else { return 0 }

    // Rightmost activity time <= t.
    var lo = 0
    var hi = activityTimes.count - 1
    var idx = -1
    while lo <= hi {
        let mid = (lo + hi) / 2
        if activityTimes[mid] <= t {
            idx = mid
            lo = mid + 1
        } else {
            hi = mid - 1
        }
    }
    guard idx >= 0 else { return 0 } // before any activity: hidden until first move

    let dtSince = t - activityTimes[idx]
    if dtSince <= idleDelay { return 1 }
    if fadeDuration <= 0 { return 0 }
    let alpha = 1 - (dtSince - idleDelay) / fadeDuration
    return min(1, max(0, alpha))
}

