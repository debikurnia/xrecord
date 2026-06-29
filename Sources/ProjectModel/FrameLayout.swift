import Foundation

/// A rectangle in top-left-origin pixel coordinates.
public struct FrameLayout: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// Computes the centered content rectangle for a canvas, inset by a per-side
/// padding fraction. The content keeps the canvas aspect ratio (no distortion).
///
/// `paddingFraction` is the margin per side as a fraction of each axis, clamped
/// to [0, 0.45]. A fraction of 0 fills the whole canvas.
public func contentLayout(canvas: ScreenSize, paddingFraction: Double) -> FrameLayout {
    let f = min(max(paddingFraction, 0), 0.45)
    let scale = 1 - 2 * f
    let width = canvas.width * scale
    let height = canvas.height * scale
    return FrameLayout(
        x: (canvas.width - width) / 2,
        y: (canvas.height - height) / 2,
        width: width,
        height: height
    )
}
