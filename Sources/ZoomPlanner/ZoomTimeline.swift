import Foundation
import ProjectModel

/// The resolved zoom state at a single instant, consumed by the renderer.
public struct ZoomState: Equatable, Sendable {
    /// Zoom factor. 1.0 means the whole screen is shown (no zoom).
    public var scale: Double
    /// Screen-space point that maps to the center of the output frame.
    public var center: Point

    public init(scale: Double, center: Point) {
        self.scale = scale
        self.center = center
    }
}

/// A focal point at a given time within a zoom segment. The segment's focus
/// path is a sequence of these, interpolated to drive panning while zoomed.
public struct FocusAnchor: Equatable, Codable, Sendable {
    public var t: Double
    public var center: Point

    public init(t: Double, center: Point) {
        self.t = t
        self.center = center
    }
}

/// A contiguous zoom event: ramp in, hold (with optional panning), ramp out.
///
/// Timeline phases:
/// ```
/// startTime ──ramp in──► rampInEnd ──hold/pan──► holdEnd ──ramp out──► endTime
/// ```
public struct ZoomSegment: Equatable, Codable, Sendable {
    public var startTime: Double
    public var rampInEnd: Double
    public var holdEnd: Double
    public var endTime: Double
    public var targetScale: Double
    /// Time-ordered focal points (at least one). The visible window pans across
    /// these while the segment is held, producing pan-instead-of-zoom-out.
    public var focusPath: [FocusAnchor]

    public init(
        startTime: Double,
        rampInEnd: Double,
        holdEnd: Double,
        endTime: Double,
        targetScale: Double,
        focusPath: [FocusAnchor]
    ) {
        self.startTime = startTime
        self.rampInEnd = rampInEnd
        self.holdEnd = holdEnd
        self.endTime = endTime
        self.targetScale = targetScale
        self.focusPath = focusPath
    }

    /// The focal point at time `t`, interpolated (eased) along the focus path.
    public func focusCenter(at t: Double) -> Point {
        guard let first = focusPath.first else {
            return Point(x: 0, y: 0)
        }
        if t <= first.t { return first.center }
        guard let last = focusPath.last else { return first.center }
        if t >= last.t { return last.center }

        for i in 1..<focusPath.count {
            let b = focusPath[i]
            if t <= b.t {
                let a = focusPath[i - 1]
                let span = b.t - a.t
                let p = span > 0 ? Easing.easeInOutCubic((t - a.t) / span) : 0
                return lerp(a.center, b.center, p)
            }
        }
        return last.center
    }
}

/// Clamps a focal point so the visible window at `scale` stays fully inside the
/// screen. At scale 1.0 the only valid center is the screen center.
public func clampCenter(_ c: Point, scale: Double, screen: ScreenSize) -> Point {
    let halfW = (screen.width / scale) / 2
    let halfH = (screen.height / scale) / 2
    let minX = halfW
    let maxX = screen.width - halfW
    let minY = halfH
    let maxY = screen.height - halfH
    let cx = minX <= maxX ? min(max(c.x, minX), maxX) : screen.width / 2
    let cy = minY <= maxY ? min(max(c.y, minY), maxY) : screen.height / 2
    return Point(x: cx, y: cy)
}

/// The full auto-zoom plan for a recording: an ordered, non-overlapping list of
/// zoom segments plus the screen geometry needed to evaluate them.
public struct ZoomTimeline: Equatable, Codable, Sendable {
    public var segments: [ZoomSegment]
    public var screen: ScreenSize
    /// Scale used outside of any segment (normally 1.0).
    public var baseScale: Double

    public init(segments: [ZoomSegment], screen: ScreenSize, baseScale: Double = 1.0) {
        self.segments = segments
        self.screen = screen
        self.baseScale = baseScale
    }

    /// Resolves the zoom state at time `t` (seconds).
    public func state(at t: Double) -> ZoomState {
        guard let seg = activeSegment(at: t) else {
            return ZoomState(scale: baseScale, center: screen.center)
        }

        let sc = screen.center
        let scale: Double
        let rawCenter: Point

        if t <= seg.rampInEnd {
            // Ramp in: scale grows from base, center glides from screen center.
            let span = seg.rampInEnd - seg.startTime
            let p = span > 0 ? Easing.easeInOutCubic((t - seg.startTime) / span) : 1
            scale = lerp(baseScale, seg.targetScale, p)
            rawCenter = lerp(sc, seg.focusCenter(at: t), p)
        } else if t <= seg.holdEnd {
            // Hold: full zoom, center follows the focus path (pan).
            scale = seg.targetScale
            rawCenter = seg.focusCenter(at: t)
        } else {
            // Ramp out: scale returns to base, center glides back to screen center.
            let span = seg.endTime - seg.holdEnd
            let p = span > 0 ? Easing.easeInOutCubic((t - seg.holdEnd) / span) : 1
            scale = lerp(seg.targetScale, baseScale, p)
            rawCenter = lerp(seg.focusCenter(at: t), sc, p)
        }

        return ZoomState(scale: scale, center: clampCenter(rawCenter, scale: scale, screen: screen))
    }

    /// Samples the timeline at a fixed frame rate, e.g. for rendering or tests.
    public func sampled(fps: Double, duration: Double) -> [ZoomState] {
        guard fps > 0, duration >= 0 else { return [] }
        let n = Int((duration * fps).rounded(.down)) + 1
        return (0..<n).map { state(at: Double($0) / fps) }
    }

    private func activeSegment(at t: Double) -> ZoomSegment? {
        for seg in segments where t >= seg.startTime && t <= seg.endTime {
            return seg
        }
        return nil
    }
}
