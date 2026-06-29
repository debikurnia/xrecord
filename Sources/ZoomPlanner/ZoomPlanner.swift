import Foundation
import ProjectModel

/// Tunable parameters for the auto-zoom planner. All durations are in seconds.
public struct ZoomPlannerConfig: Sendable {
    /// Zoom factor applied during a segment's hold phase.
    public var targetScale: Double
    /// Time to ramp from base scale to `targetScale`.
    public var rampInDuration: Double
    /// Time to ramp back from `targetScale` to base scale.
    public var rampOutDuration: Double
    /// Start zooming this many seconds before the first click in a cluster.
    public var leadIn: Double
    /// Keep zoomed in this many seconds after the last click in a cluster.
    public var holdAfterLastClick: Double
    /// Clicks no more than this far apart in time belong to the same cluster.
    public var clusterTimeGap: Double
    /// Minimum total duration of a generated segment.
    public var minSegmentDuration: Double
    /// If two adjacent segments are closer than this, merge them and pan
    /// between focal points instead of zooming out and back in (anti-jitter).
    public var mergeSegmentGap: Double
    /// When true, the focus path follows captured cursor samples during the
    /// hold phase; otherwise it follows the click positions.
    public var cursorFollow: Bool

    public init(
        targetScale: Double = 1.8,
        rampInDuration: Double = 0.5,
        rampOutDuration: Double = 0.5,
        leadIn: Double = 0.3,
        holdAfterLastClick: Double = 0.8,
        clusterTimeGap: Double = 1.5,
        minSegmentDuration: Double = 0.6,
        mergeSegmentGap: Double = 1.0,
        cursorFollow: Bool = true
    ) {
        self.targetScale = targetScale
        self.rampInDuration = rampInDuration
        self.rampOutDuration = rampOutDuration
        self.leadIn = leadIn
        self.holdAfterLastClick = holdAfterLastClick
        self.clusterTimeGap = clusterTimeGap
        self.minSegmentDuration = minSegmentDuration
        self.mergeSegmentGap = mergeSegmentGap
        self.cursorFollow = cursorFollow
    }
}

/// Generates an auto-zoom plan from captured clicks and cursor movement.
///
/// Pipeline:
/// 1. Cluster clicks that are close together in time.
/// 2. Turn each cluster into a zoom segment (lead-in, ramp, hold, ramp-out).
/// 3. Merge adjacent segments that are too close, panning between their focal
///    points instead of zooming out and back in.
public struct ZoomPlanner {
    public var config: ZoomPlannerConfig

    public init(config: ZoomPlannerConfig = ZoomPlannerConfig()) {
        self.config = config
    }

    public func plan(
        clicks: [ClickEvent],
        cursor: [CursorSample],
        keys: [KeyEvent] = [],
        screen: ScreenSize,
        duration: Double
    ) -> ZoomTimeline {
        // Clicks and keypresses are both "activity": each can trigger or sustain
        // a zoom. Typing keeps the zoom engaged near the cursor's location.
        var events: [ActivityEvent] = clicks.map { ActivityEvent(t: $0.t, position: $0.position) }
        events += keys.map { ActivityEvent(t: $0.t, position: $0.position) }
        let sorted = events.sorted { $0.t < $1.t }
        let clusters = clusterByTime(sorted)
        var segments = clusters.map {
            makeSegment(cluster: $0, cursor: cursor, screen: screen, duration: duration)
        }
        segments = mergeClose(segments)
        return ZoomTimeline(segments: segments, screen: screen, baseScale: 1.0)
    }

    /// A click or keypress, reduced to a time and a screen location.
    private struct ActivityEvent {
        var t: Double
        var position: Point
    }

    // MARK: - Step 1: clustering

    private func clusterByTime(_ sorted: [ActivityEvent]) -> [[ActivityEvent]] {
        var clusters: [[ActivityEvent]] = []
        for event in sorted {
            if let prev = clusters.last?.last, event.t - prev.t <= config.clusterTimeGap {
                clusters[clusters.count - 1].append(event)
            } else {
                clusters.append([event])
            }
        }
        return clusters
    }

    // MARK: - Step 2: segment generation

    private func makeSegment(
        cluster: [ActivityEvent],
        cursor: [CursorSample],
        screen: ScreenSize,
        duration: Double
    ) -> ZoomSegment {
        let spanStart = cluster.first!.t
        let spanEnd = cluster.last!.t

        let startTime = max(0, spanStart - config.leadIn)
        var rampInEnd = startTime + config.rampInDuration
        var holdEnd = spanEnd + config.holdAfterLastClick
        var endTime = holdEnd + config.rampOutDuration

        // Enforce a minimum overall duration by extending the hold.
        if endTime - startTime < config.minSegmentDuration {
            holdEnd = startTime + config.minSegmentDuration - config.rampOutDuration
            endTime = holdEnd + config.rampOutDuration
        }

        // Clamp to the recording bounds and keep phase ordering valid.
        if duration > 0 {
            endTime = min(endTime, duration)
        }
        holdEnd = min(holdEnd, endTime)
        rampInEnd = min(rampInEnd, holdEnd)

        let focusPath = buildFocusPath(
            cluster: cluster,
            cursor: cursor,
            startTime: startTime,
            holdEnd: holdEnd,
            screen: screen
        )

        return ZoomSegment(
            startTime: startTime,
            rampInEnd: rampInEnd,
            holdEnd: holdEnd,
            endTime: endTime,
            targetScale: config.targetScale,
            focusPath: focusPath
        )
    }

    private func buildFocusPath(
        cluster: [ActivityEvent],
        cursor: [CursorSample],
        startTime: Double,
        holdEnd: Double,
        screen: ScreenSize
    ) -> [FocusAnchor] {
        if config.cursorFollow {
            let inRange = cursor.filter { $0.t >= startTime && $0.t <= holdEnd }
            if !inRange.isEmpty {
                return inRange.map {
                    FocusAnchor(
                        t: $0.t,
                        center: clampCenter($0.position, scale: config.targetScale, screen: screen)
                    )
                }
            }
        }
        // Fallback (or cursorFollow disabled): anchor on the click positions.
        return cluster.map {
            FocusAnchor(
                t: $0.t,
                center: clampCenter($0.position, scale: config.targetScale, screen: screen)
            )
        }
    }

    // MARK: - Step 3: anti-jitter merge

    private func mergeClose(_ segments: [ZoomSegment]) -> [ZoomSegment] {
        guard var current = segments.first else { return [] }
        var result: [ZoomSegment] = []

        for seg in segments.dropFirst() {
            if seg.startTime - current.endTime < config.mergeSegmentGap {
                // Merge: keep one ramp-in, extend hold to cover both, pan across
                // the combined focal points, ramp out only at the very end.
                current.holdEnd = seg.holdEnd
                current.endTime = seg.endTime
                current.targetScale = max(current.targetScale, seg.targetScale)
                current.focusPath = (current.focusPath + seg.focusPath).sorted { $0.t < $1.t }
            } else {
                result.append(current)
                current = seg
            }
        }
        result.append(current)
        return result
    }
}
