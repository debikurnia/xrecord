import Foundation

/// Which mouse button produced a click event.
public enum MouseButton: String, Codable, Sendable {
    case left
    case right
    case other
}

/// A single sample of the cursor position at a point in time.
public struct CursorSample: Equatable, Codable, Sendable {
    /// Timestamp in seconds, relative to the start of the recording.
    public var t: Double
    public var position: Point

    public init(t: Double, position: Point) {
        self.t = t
        self.position = position
    }
}

/// A mouse click captured during the recording.
public struct ClickEvent: Equatable, Codable, Sendable {
    /// Timestamp in seconds, relative to the start of the recording.
    public var t: Double
    public var position: Point
    public var button: MouseButton

    public init(t: Double, position: Point, button: MouseButton = .left) {
        self.t = t
        self.position = position
        self.button = button
    }
}

/// A keypress captured during the recording. Only the TIMING and the cursor
/// position at that moment are recorded; the key code / character is never
/// captured. This drives activity-based auto-zoom (e.g. zooming while typing),
/// not keystroke logging.
public struct KeyEvent: Equatable, Codable, Sendable {
    /// Timestamp in seconds, relative to the start of the recording.
    public var t: Double
    /// Cursor position (native pixels) at the time of the keypress.
    public var position: Point

    public init(t: Double, position: Point) {
        self.t = t
        self.position = position
    }
}

/// The sidecar metadata produced alongside a raw screen recording.
///
/// This is the bridge between the capture stage and the render stage: it holds
/// everything the renderer needs to reconstruct an edited video from raw frames.
public struct RecordingMetadata: Equatable, Codable, Sendable {
    /// Frames per second of the raw recording.
    public var fps: Double
    /// Backing-scale factor of the captured display (e.g. 2.0 for Retina).
    public var displayScale: Double
    /// Captured screen dimensions in native pixels.
    public var screen: ScreenSize
    /// Total duration of the recording in seconds.
    public var duration: Double
    /// Time-ordered cursor position samples.
    public var cursor: [CursorSample]
    /// Time-ordered click events.
    public var clicks: [ClickEvent]
    /// Time-ordered keypress activity (timing + cursor position only, no key codes).
    public var keys: [KeyEvent]
    /// Whether the system cursor is baked into the raw video. When false, the
    /// renderer is expected to draw its own (smoothed, enlarged) cursor.
    public var cursorBaked: Bool

    public init(
        fps: Double,
        displayScale: Double,
        screen: ScreenSize,
        duration: Double,
        cursor: [CursorSample],
        clicks: [ClickEvent],
        keys: [KeyEvent] = [],
        cursorBaked: Bool = true
    ) {
        self.fps = fps
        self.displayScale = displayScale
        self.screen = screen
        self.duration = duration
        self.cursor = cursor
        self.clicks = clicks
        self.keys = keys
        self.cursorBaked = cursorBaked
    }

    // Custom decoding so recordings written before `cursorBaked`/`keys` existed
    // still load (treated as baked, with no typing activity).
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fps = try container.decode(Double.self, forKey: .fps)
        displayScale = try container.decode(Double.self, forKey: .displayScale)
        screen = try container.decode(ScreenSize.self, forKey: .screen)
        duration = try container.decode(Double.self, forKey: .duration)
        cursor = try container.decode([CursorSample].self, forKey: .cursor)
        clicks = try container.decode([ClickEvent].self, forKey: .clicks)
        keys = try container.decodeIfPresent([KeyEvent].self, forKey: .keys) ?? []
        cursorBaked = try container.decodeIfPresent(Bool.self, forKey: .cursorBaked) ?? true
    }
}
