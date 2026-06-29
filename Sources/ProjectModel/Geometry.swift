import Foundation

/// A 2D point in screen pixel coordinates (origin top-left).
public struct Point: Equatable, Codable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// Dimensions of the captured screen in pixels (native resolution).
public struct ScreenSize: Equatable, Codable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    /// The geometric center of the screen.
    public var center: Point {
        Point(x: width / 2, y: height / 2)
    }
}

/// Linear interpolation between two scalars. `t` is expected in [0, 1].
@inlinable
public func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
    a + (b - a) * t
}

/// Linear interpolation between two points. `t` is expected in [0, 1].
@inlinable
public func lerp(_ a: Point, _ b: Point, _ t: Double) -> Point {
    Point(x: lerp(a.x, b.x, t), y: lerp(a.y, b.y, t))
}
