import Testing
import Foundation
import CoreGraphics
import ProjectModel
@testable import ZoomPlanner

private func close(_ a: Double, _ b: Double, _ tol: Double = 1e-6) -> Bool {
    abs(a - b) <= tol
}

@Suite struct ZoomTransformTests {
    let screen = ScreenSize(width: 2000, height: 1000)

    @Test func focalPointMapsToOutputCenter() {
        let state = ZoomState(scale: 1.8, center: Point(x: 1000, y: 500))
        let tf = state.ciTransform(screen: screen)

        // Focal point in CI space (y flipped): (1000, 1000-500=500).
        let mapped = CGPoint(x: 1000, y: 500).applying(tf)
        #expect(close(Double(mapped.x), 1000)) // screen.width/2
        #expect(close(Double(mapped.y), 500))  // screen.height/2
    }

    @Test func scaleFactorIsApplied() {
        let state = ZoomState(scale: 1.8, center: Point(x: 1000, y: 500))
        let tf = state.ciTransform(screen: screen)

        // A point 10px right of the focal point should land 1.8*10 right of center.
        let mapped = CGPoint(x: 1010, y: 500).applying(tf)
        #expect(close(Double(mapped.x), 1000 + 1.8 * 10))
        #expect(close(Double(mapped.y), 500))
    }

    @Test func identityWhenNotZoomed() {
        // scale 1.0 centered on the screen center → identity transform.
        let state = ZoomState(scale: 1.0, center: screen.center)
        let tf = state.ciTransform(screen: screen)

        let p = CGPoint(x: 1234, y: 678)
        let mapped = p.applying(tf)
        #expect(close(Double(mapped.x), 1234))
        #expect(close(Double(mapped.y), 678))
    }

    @Test func yAxisIsFlippedForOffCenterFocus() {
        // Focal point high on screen (small y, top) should map a CI-space point.
        let state = ZoomState(scale: 2.0, center: Point(x: 500, y: 100))
        let tf = state.ciTransform(screen: screen)

        // CI-space focal y = 1000 - 100 = 900.
        let mapped = CGPoint(x: 500, y: 900).applying(tf)
        #expect(close(Double(mapped.x), 1000))
        #expect(close(Double(mapped.y), 500))
    }
}
