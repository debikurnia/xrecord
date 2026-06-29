import Testing
import Foundation
import ProjectModel
@testable import CursorSmoother

private func close(_ a: Double, _ b: Double, _ tol: Double = 1e-6) -> Bool {
    abs(a - b) <= tol
}

@Suite struct CursorSmootherTests {
    @Test func emptyStaysEmpty() {
        let out = CursorSmoother(sigma: 0.1).smooth([])
        #expect(out.isEmpty)
    }

    @Test func tinyTrackUnchanged() {
        let samples = [
            CursorSample(t: 0.0, position: Point(x: 0, y: 0)),
            CursorSample(t: 0.1, position: Point(x: 100, y: 0)),
        ]
        let out = CursorSmoother(sigma: 0.1).smooth(samples)
        #expect(out == samples) // count <= 2 short-circuits
    }

    @Test func keepsSampleCountAndTimes() {
        var samples: [CursorSample] = []
        for i in 0..<20 { samples.append(CursorSample(t: Double(i) * 0.016, position: Point(x: Double(i), y: 0))) }
        let out = CursorSmoother(sigma: 0.05).smooth(samples)
        #expect(out.count == samples.count)
        #expect(zip(out, samples).allSatisfy { close($0.t, $1.t) })
    }

    @Test func reducesSpike() {
        // Flat line at y=0 with a single y=100 spike in the middle.
        var samples: [CursorSample] = []
        for i in 0..<21 {
            let y = (i == 10) ? 100.0 : 0.0
            samples.append(CursorSample(t: Double(i) * 0.016, position: Point(x: Double(i), y: y)))
        }
        let out = CursorSmoother(sigma: 0.05).smooth(samples)
        // The spike should be pulled down substantially.
        #expect(out[10].position.y < 60)
        #expect(out[10].position.y > 0)
    }

    @Test func preservesLinearRampInInterior() {
        // A straight diagonal line; interior points should stay ~on the line.
        var samples: [CursorSample] = []
        for i in 0..<40 {
            let t = Double(i) * 0.016
            samples.append(CursorSample(t: t, position: Point(x: Double(i) * 10, y: Double(i) * 5)))
        }
        let out = CursorSmoother(sigma: 0.03).smooth(samples)
        let mid = out[20]
        #expect(close(mid.position.x, 200, 5)) // ~20*10
        #expect(close(mid.position.y, 100, 5)) // ~20*5
    }

    // MARK: - SmoothedCursor querying

    @Test func positionInterpolatesBetweenSamples() {
        let cursor = SmoothedCursor(samples: [
            CursorSample(t: 1.0, position: Point(x: 0, y: 0)),
            CursorSample(t: 2.0, position: Point(x: 100, y: 200)),
        ])
        let mid = cursor.position(at: 1.5)
        #expect(mid != nil)
        #expect(close(mid!.x, 50))
        #expect(close(mid!.y, 100))
    }

    @Test func positionClampsOutsideRange() {
        let cursor = SmoothedCursor(samples: [
            CursorSample(t: 1.0, position: Point(x: 10, y: 20)),
            CursorSample(t: 2.0, position: Point(x: 90, y: 80)),
        ])
        #expect(cursor.position(at: 0.0)?.x == 10) // before → first
        #expect(cursor.position(at: 5.0)?.x == 90) // after → last
    }

    @Test func positionNilWhenEmpty() {
        let cursor = SmoothedCursor(samples: [])
        #expect(cursor.position(at: 1.0) == nil)
    }

    @Test func sortsUnorderedSamples() {
        let cursor = SmoothedCursor(samples: [
            CursorSample(t: 2.0, position: Point(x: 100, y: 0)),
            CursorSample(t: 1.0, position: Point(x: 0, y: 0)),
        ])
        #expect(close(cursor.position(at: 1.5)!.x, 50))
    }
}
