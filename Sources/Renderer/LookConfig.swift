import Foundation

/// The background fill behind the recorded content.
public enum Background: Equatable, Sendable {
    /// No fill (renders as black in an opaque MP4).
    case transparent
    case solid(r: Double, g: Double, b: Double)
    case gradient(r0: Double, g0: Double, b0: Double, r1: Double, g1: Double, b1: Double)
    case image(URL)

    /// Parses a CLI spec:
    /// - `none`
    /// - `solid:RRGGBB`
    /// - `gradient:RRGGBB,RRGGBB`
    /// - `image:/path/to/file`
    public static func parse(_ spec: String) -> Background? {
        if spec == "none" { return .transparent }

        let parts = spec.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        let kind = parts[0]
        let value = parts[1]

        switch kind {
        case "solid":
            guard let c = hexRGB(value) else { return nil }
            return .solid(r: c.0, g: c.1, b: c.2)
        case "gradient":
            let colors = value.split(separator: ",").map(String.init)
            guard colors.count == 2,
                  let c0 = hexRGB(colors[0]),
                  let c1 = hexRGB(colors[1]) else { return nil }
            return .gradient(r0: c0.0, g0: c0.1, b0: c0.2, r1: c1.0, g1: c1.1, b1: c1.2)
        case "image":
            guard !value.isEmpty else { return nil }
            return .image(URL(fileURLWithPath: value))
        default:
            return nil
        }
    }

    /// Parses a 6-digit hex color (optionally prefixed with `#`) to 0...1 RGB.
    public static func hexRGB(_ hex: String) -> (Double, Double, Double)? {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        return (r, g, b)
    }
}

/// Visual styling applied around the recorded content during rendering.
public struct LookConfig: Sendable {
    public var background: Background
    /// Per-side inset as a fraction of each axis (0 = full-bleed).
    public var paddingFraction: Double
    /// Corner radius of the content, in output pixels.
    public var cornerRadius: Double
    /// Drop-shadow opacity (0 = no shadow).
    public var shadowOpacity: Double
    /// Gaussian blur radius of the shadow, in output pixels.
    public var shadowRadius: Double
    /// Downward shadow offset, in output pixels.
    public var shadowOffset: Double
    /// Size multiplier for the rendered cursor (relative to its base size).
    public var cursorScale: Double
    /// When true, the cursor fades out while the mouse is idle (macOS-like).
    public var cursorHide: Bool
    /// Seconds of no mouse activity before the cursor starts fading out.
    public var cursorHideDelay: Double
    /// Whether to draw an expanding ripple at each click.
    public var clickEffect: Bool
    /// Motion-blur strength during fast zoom/pan (0 = off).
    public var motionBlur: Double

    public init(
        background: Background,
        paddingFraction: Double,
        cornerRadius: Double,
        shadowOpacity: Double,
        shadowRadius: Double,
        shadowOffset: Double,
        cursorScale: Double = 1.5,
        cursorHide: Bool = true,
        cursorHideDelay: Double = 0.6,
        clickEffect: Bool = true,
        motionBlur: Double = 0.5
    ) {
        self.background = background
        self.paddingFraction = paddingFraction
        self.cornerRadius = cornerRadius
        self.shadowOpacity = shadowOpacity
        self.shadowRadius = shadowRadius
        self.shadowOffset = shadowOffset
        self.cursorScale = cursorScale
        self.cursorHide = cursorHide
        self.cursorHideDelay = cursorHideDelay
        self.clickEffect = clickEffect
        self.motionBlur = motionBlur
    }

    /// The default tasteful neutral slate gradient (#5B6172 → #33363F).
    public static let defaultBackground = Background.gradient(
        r0: 0x5B / 255.0, g0: 0x61 / 255.0, b0: 0x72 / 255.0,
        r1: 0x33 / 255.0, g1: 0x36 / 255.0, b1: 0x3F / 255.0
    )
}
