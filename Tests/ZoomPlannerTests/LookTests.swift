import Testing
import Foundation
import ProjectModel
@testable import Renderer

private func close(_ a: Double, _ b: Double, _ tol: Double = 1e-9) -> Bool {
    abs(a - b) <= tol
}

@Suite struct FrameLayoutTests {
    @Test func centeredContentWithPadding() {
        let layout = contentLayout(canvas: ScreenSize(width: 2000, height: 1000), paddingFraction: 0.1)
        #expect(close(layout.width, 1600))  // 2000 * 0.8
        #expect(close(layout.height, 800))  // 1000 * 0.8
        #expect(close(layout.x, 200))       // (2000-1600)/2
        #expect(close(layout.y, 100))       // (1000-800)/2
    }

    @Test func zeroPaddingFillsCanvas() {
        let canvas = ScreenSize(width: 2940, height: 1912)
        let layout = contentLayout(canvas: canvas, paddingFraction: 0)
        #expect(close(layout.width, 2940))
        #expect(close(layout.height, 1912))
        #expect(close(layout.x, 0))
        #expect(close(layout.y, 0))
    }

    @Test func paddingFractionIsClamped() {
        let canvas = ScreenSize(width: 1000, height: 1000)
        let layout = contentLayout(canvas: canvas, paddingFraction: 0.9) // clamps to 0.45
        #expect(close(layout.width, 100))  // 1000 * (1 - 0.9)
        #expect(close(layout.height, 100))
    }

    @Test func preservesAspectRatio() {
        let canvas = ScreenSize(width: 2940, height: 1912)
        let layout = contentLayout(canvas: canvas, paddingFraction: 0.06)
        let canvasAspect = canvas.width / canvas.height
        let contentAspect = layout.width / layout.height
        #expect(close(canvasAspect, contentAspect, 1e-9))
    }
}

@Suite struct BackgroundParseTests {
    @Test func parsesNone() {
        #expect(Background.parse("none") == .transparent)
    }

    @Test func parsesSolidHex() {
        #expect(Background.parse("solid:FF0000") == .solid(r: 1, g: 0, b: 0))
        #expect(Background.parse("solid:#00FF00") == .solid(r: 0, g: 1, b: 0))
    }

    @Test func parsesGradient() {
        let bg = Background.parse("gradient:000000,FFFFFF")
        #expect(bg == .gradient(r0: 0, g0: 0, b0: 0, r1: 1, g1: 1, b1: 1))
    }

    @Test func parsesImagePath() {
        #expect(Background.parse("image:/tmp/bg.png") == .image(URL(fileURLWithPath: "/tmp/bg.png")))
    }

    @Test func rejectsInvalidSpecs() {
        #expect(Background.parse("solid:ZZZ") == nil)
        #expect(Background.parse("solid:12345") == nil)   // wrong length
        #expect(Background.parse("gradient:FF0000") == nil) // needs two colors
        #expect(Background.parse("bogus") == nil)
        #expect(Background.parse("image:") == nil)
    }

    @Test func hexParsingComputesChannels() {
        let c = Background.hexRGB("336699")
        #expect(c != nil)
        #expect(close(c!.0, Double(0x33) / 255.0))
        #expect(close(c!.1, Double(0x66) / 255.0))
        #expect(close(c!.2, Double(0x99) / 255.0))
    }
}
