import Testing
import Foundation
import ProjectModel
@testable import ZoomPlanner

/// Approximate equality helper (Swift Testing has no built-in accuracy form).
private func close(_ a: Double, _ b: Double, _ tol: Double = 1e-9) -> Bool {
    abs(a - b) <= tol
}

@Suite struct ZoomPlannerTests {
    let screen = ScreenSize(width: 2000, height: 1000)

    private func makePlanner(cursorFollow: Bool = false) -> ZoomPlanner {
        var cfg = ZoomPlannerConfig()
        cfg.cursorFollow = cursorFollow
        return ZoomPlanner(config: cfg)
    }

    // MARK: - No input

    @Test func noClicksProducesNoZoom() {
        let timeline = makePlanner().plan(clicks: [], cursor: [], screen: screen, duration: 5)
        #expect(timeline.segments.isEmpty)

        let s = timeline.state(at: 2.5)
        #expect(close(s.scale, 1.0))
        #expect(close(s.center.x, 1000, 1e-6))
        #expect(close(s.center.y, 500, 1e-6))
    }

    // MARK: - Single click

    @Test func singleClickSegmentTimings() {
        let click = ClickEvent(t: 2.0, position: Point(x: 1000, y: 500))
        let timeline = makePlanner().plan(clicks: [click], cursor: [], screen: screen, duration: 10)

        #expect(timeline.segments.count == 1)
        let seg = timeline.segments[0]
        #expect(close(seg.startTime, 1.7))  // 2.0 - leadIn 0.3
        #expect(close(seg.rampInEnd, 2.2))  // 1.7 + ramp 0.5
        #expect(close(seg.holdEnd, 2.8))    // 2.0 + hold 0.8
        #expect(close(seg.endTime, 3.3))    // 2.8 + ramp 0.5
    }

    @Test func singleClickScaleProfile() {
        let click = ClickEvent(t: 2.0, position: Point(x: 1000, y: 500))
        let timeline = makePlanner().plan(clicks: [click], cursor: [], screen: screen, duration: 10)

        #expect(close(timeline.state(at: 0.0).scale, 1.0))   // before
        #expect(close(timeline.state(at: 1.7).scale, 1.0))   // ramp start
        #expect(close(timeline.state(at: 2.5).scale, 1.8))   // hold
        #expect(close(timeline.state(at: 3.3).scale, 1.0))   // ramp end
        #expect(close(timeline.state(at: 5.0).scale, 1.0))   // after

        // Center is the click position during hold (inside clamp range).
        let hold = timeline.state(at: 2.5)
        #expect(close(hold.center.x, 1000, 1e-6))
        #expect(close(hold.center.y, 500, 1e-6))
    }

    @Test func rampInIsMonotonicIncreasing() {
        let click = ClickEvent(t: 2.0, position: Point(x: 1000, y: 500))
        let timeline = makePlanner().plan(clicks: [click], cursor: [], screen: screen, duration: 10)

        let a = timeline.state(at: 1.8).scale
        let b = timeline.state(at: 2.0).scale
        let c = timeline.state(at: 2.15).scale
        #expect(a < b)
        #expect(b < c)
    }

    @Test func scaleStaysWithinBounds() {
        let click = ClickEvent(t: 2.0, position: Point(x: 1000, y: 500))
        let timeline = makePlanner().plan(clicks: [click], cursor: [], screen: screen, duration: 10)

        for i in 0...100 {
            let s = timeline.state(at: Double(i) / 10.0).scale
            #expect(s >= 1.0 - 1e-9)
            #expect(s <= 1.8 + 1e-9)
        }
    }

    // MARK: - Clustering

    @Test func nearbyClicksMergeIntoOneCluster() {
        let clicks = [
            ClickEvent(t: 2.0, position: Point(x: 1000, y: 500)),
            ClickEvent(t: 2.5, position: Point(x: 1010, y: 510)), // gap 0.5 <= 1.5
        ]
        let timeline = makePlanner().plan(clicks: clicks, cursor: [], screen: screen, duration: 10)

        #expect(timeline.segments.count == 1)
        let seg = timeline.segments[0]
        #expect(close(seg.startTime, 1.7)) // 2.0 - 0.3
        #expect(close(seg.holdEnd, 3.3))   // 2.5 + 0.8
    }

    @Test func distantClustersStaySeparate() {
        let clicks = [
            ClickEvent(t: 2.0, position: Point(x: 600, y: 500)),
            ClickEvent(t: 10.0, position: Point(x: 1400, y: 500)),
        ]
        let timeline = makePlanner().plan(clicks: clicks, cursor: [], screen: screen, duration: 15)

        #expect(timeline.segments.count == 2)
        // Fully zoomed out between the two separate segments.
        #expect(close(timeline.state(at: 6.0).scale, 1.0))
    }

    // MARK: - Anti-jitter merge (pan instead of zoom-out)

    @Test func closeSegmentsMergeAndPanInsteadOfZoomingOut() {
        let a = Point(x: 600, y: 500)
        let b = Point(x: 1400, y: 500)
        let clicks = [
            ClickEvent(t: 2.0, position: a),
            ClickEvent(t: 4.0, position: b), // gap 2.0 > clusterTimeGap → separate clusters
        ]
        let timeline = makePlanner().plan(clicks: clicks, cursor: [], screen: screen, duration: 10)

        // seg1 ends at 3.3, seg2 starts at 3.7 → gap 0.4 < mergeSegmentGap 1.0 → merged.
        #expect(timeline.segments.count == 1)
        let seg = timeline.segments[0]
        #expect(close(seg.startTime, 1.7))
        #expect(close(seg.endTime, 5.3)) // 4.0 + 0.8 + 0.5

        // Between the two clicks we are still zoomed in (no zoom-out dip)...
        let mid = timeline.state(at: 3.0)
        #expect(close(mid.scale, 1.8))
        // ...and the center has panned from A toward B.
        #expect(mid.center.x > a.x)
        #expect(mid.center.x < b.x)
    }

    // MARK: - Cursor follow

    @Test func cursorFollowPansWithCursorDuringHold() {
        let click = ClickEvent(t: 2.0, position: Point(x: 1000, y: 500))
        // Cursor drifts right during the hold window.
        var cursor: [CursorSample] = []
        var t = 1.7
        while t <= 2.8 {
            let x = 1000 + (t - 2.0) * 200 // moves right after the click
            cursor.append(CursorSample(t: t, position: Point(x: x, y: 500)))
            t += 0.05
        }

        let timeline = makePlanner(cursorFollow: true)
            .plan(clicks: [click], cursor: cursor, screen: screen, duration: 10)

        let late = timeline.state(at: 2.6)
        #expect(close(late.scale, 1.8))
        #expect(late.center.x > 1000) // tracked the moving cursor
    }

    // MARK: - Edge clamping

    @Test func centerClampedNearScreenCorner() {
        let click = ClickEvent(t: 2.0, position: Point(x: 1990, y: 990))
        let timeline = makePlanner().plan(clicks: [click], cursor: [], screen: screen, duration: 10)

        let s = timeline.state(at: 2.5)
        // maxX = 2000 - (2000/1.8)/2 = 1444.444..., maxY = 1000 - (1000/1.8)/2 = 722.222...
        #expect(close(s.center.x, 2000 - (2000 / 1.8) / 2, 1e-3))
        #expect(close(s.center.y, 1000 - (1000 / 1.8) / 2, 1e-3))
    }

    // MARK: - Numerical sanity

    @Test func sampledTimelineIsAllFinite() {
        let clicks = [
            ClickEvent(t: 1.0, position: Point(x: 100, y: 100)),
            ClickEvent(t: 4.0, position: Point(x: 1900, y: 900)),
        ]
        let timeline = makePlanner().plan(clicks: clicks, cursor: [], screen: screen, duration: 8)

        let states = timeline.sampled(fps: 60, duration: 8)
        #expect(!states.isEmpty)
        for st in states {
            #expect(st.scale.isFinite)
            #expect(st.center.x.isFinite)
            #expect(st.center.y.isFinite)
            #expect(st.scale >= 1.0 - 1e-9)
        }
    }

    // MARK: - Persistence

    @Test func timelineCodableRoundTrip() throws {
        let click = ClickEvent(t: 2.0, position: Point(x: 1000, y: 500))
        let timeline = makePlanner().plan(clicks: [click], cursor: [], screen: screen, duration: 10)

        let data = try JSONEncoder().encode(timeline)
        let decoded = try JSONDecoder().decode(ZoomTimeline.self, from: data)
        #expect(decoded == timeline)
    }

    // MARK: - Easing

    @Test func easeInOutCubicEndpointsAndMidpoint() {
        #expect(close(Easing.easeInOutCubic(0), 0))
        #expect(close(Easing.easeInOutCubic(1), 1))
        #expect(close(Easing.easeInOutCubic(0.5), 0.5))
        // Clamps out-of-range input.
        #expect(close(Easing.easeInOutCubic(-1), 0))
        #expect(close(Easing.easeInOutCubic(2), 1))
    }

    // MARK: - Activity (typing) zoom

    @Test func typingAloneCreatesZoomSegment() {
        let keys = [
            KeyEvent(t: 2.0, position: Point(x: 800, y: 400)),
            KeyEvent(t: 2.3, position: Point(x: 800, y: 400)),
            KeyEvent(t: 2.6, position: Point(x: 800, y: 400)),
        ]
        let timeline = makePlanner().plan(clicks: [], cursor: [], keys: keys, screen: screen, duration: 10)
        #expect(timeline.segments.count == 1)
        let hold = timeline.state(at: 2.4)
        #expect(close(hold.scale, 1.8))
        #expect(close(hold.center.x, 800, 1e-6))
        #expect(close(hold.center.y, 400, 1e-6))
    }

    @Test func typingMergesWithNearbyClickIntoOneSegment() {
        let clicks = [ClickEvent(t: 2.0, position: Point(x: 600, y: 500))]
        let keys = [
            KeyEvent(t: 2.5, position: Point(x: 620, y: 500)),
            KeyEvent(t: 3.0, position: Point(x: 620, y: 500)),
        ]
        let timeline = makePlanner().plan(clicks: clicks, cursor: [], keys: keys, screen: screen, duration: 10)
        #expect(timeline.segments.count == 1)
        // Still zoomed while typing continues after the click.
        #expect(close(timeline.state(at: 2.8).scale, 1.8))
    }

    @Test func emptyKeysMatchClicksOnlyBehavior() {
        let clicks = [ClickEvent(t: 2.0, position: Point(x: 1000, y: 500))]
        let a = makePlanner().plan(clicks: clicks, cursor: [], screen: screen, duration: 10)
        let b = makePlanner().plan(clicks: clicks, cursor: [], keys: [], screen: screen, duration: 10)
        #expect(a.segments.count == b.segments.count)
        #expect(close(a.state(at: 2.5).scale, b.state(at: 2.5).scale))
    }
}
