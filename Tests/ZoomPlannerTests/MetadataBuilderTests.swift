import Testing
import Foundation
import ProjectModel

private func close(_ a: Double, _ b: Double, _ tol: Double = 1e-9) -> Bool {
    abs(a - b) <= tol
}

@Suite struct MetadataBuilderTests {
    private let screen = ScreenSize(width: 2880, height: 1800)

    @Test func normalizesTimestampsRelativeToSessionStart() {
        let cursor = [
            RawCursorSample(hostTime: 100.0, pointX: 10, pointY: 20),
            RawCursorSample(hostTime: 101.5, pointX: 30, pointY: 40),
        ]
        let meta = MetadataBuilder.build(
            fps: 60, displayScale: 2.0, screen: screen,
            sessionStart: 100.0, sessionEnd: 105.0,
            rawCursor: cursor, rawClicks: []
        )

        #expect(meta.cursor.count == 2)
        #expect(close(meta.cursor[0].t, 0.0))
        #expect(close(meta.cursor[1].t, 1.5))
        #expect(close(meta.duration, 5.0))
    }

    @Test func mapsPointsToNativePixelsUsingScale() {
        let clicks = [RawClick(hostTime: 102.0, pointX: 100, pointY: 50, button: .left)]
        let meta = MetadataBuilder.build(
            fps: 60, displayScale: 2.0, screen: screen,
            sessionStart: 100.0, sessionEnd: 105.0,
            rawCursor: [], rawClicks: clicks
        )

        #expect(meta.clicks.count == 1)
        #expect(close(meta.clicks[0].position.x, 200)) // 100 * 2.0
        #expect(close(meta.clicks[0].position.y, 100)) // 50 * 2.0
        #expect(close(meta.clicks[0].t, 2.0))
        #expect(meta.clicks[0].button == .left)
    }

    @Test func dropsSamplesBeforeSessionStart() {
        let cursor = [
            RawCursorSample(hostTime: 99.0, pointX: 1, pointY: 1),   // before first frame
            RawCursorSample(hostTime: 100.5, pointX: 2, pointY: 2),  // valid
        ]
        let clicks = [
            RawClick(hostTime: 99.5, pointX: 1, pointY: 1, button: .left), // dropped
        ]
        let meta = MetadataBuilder.build(
            fps: 60, displayScale: 1.0, screen: screen,
            sessionStart: 100.0, sessionEnd: 102.0,
            rawCursor: cursor, rawClicks: clicks
        )

        #expect(meta.cursor.count == 1)
        #expect(close(meta.cursor[0].t, 0.5))
        #expect(meta.clicks.isEmpty)
    }

    @Test func clampsNegativeDurationToZero() {
        let meta = MetadataBuilder.build(
            fps: 60, displayScale: 1.0, screen: screen,
            sessionStart: 100.0, sessionEnd: 99.0, // end before start
            rawCursor: [], rawClicks: []
        )
        #expect(close(meta.duration, 0.0))
    }

    @Test func resultIsTimeSorted() {
        let cursor = [
            RawCursorSample(hostTime: 103.0, pointX: 1, pointY: 1),
            RawCursorSample(hostTime: 101.0, pointX: 2, pointY: 2),
            RawCursorSample(hostTime: 102.0, pointX: 3, pointY: 3),
        ]
        let meta = MetadataBuilder.build(
            fps: 60, displayScale: 1.0, screen: screen,
            sessionStart: 100.0, sessionEnd: 105.0,
            rawCursor: cursor, rawClicks: []
        )
        let times = meta.cursor.map { $0.t }
        #expect(times == times.sorted())
    }
}
