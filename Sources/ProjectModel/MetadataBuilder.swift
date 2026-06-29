import Foundation

/// A raw cursor sample as captured by the input tracker, before normalization.
/// `hostTime` is in seconds on the host clock (e.g. CACurrentMediaTime()).
/// `pointX`/`pointY` are global display coordinates in points (top-left origin).
public struct RawCursorSample: Equatable, Sendable {
    public var hostTime: Double
    public var pointX: Double
    public var pointY: Double

    public init(hostTime: Double, pointX: Double, pointY: Double) {
        self.hostTime = hostTime
        self.pointX = pointX
        self.pointY = pointY
    }
}

/// A raw click as captured by the input tracker, before normalization.
public struct RawClick: Equatable, Sendable {
    public var hostTime: Double
    public var pointX: Double
    public var pointY: Double
    public var button: MouseButton

    public init(hostTime: Double, pointX: Double, pointY: Double, button: MouseButton) {
        self.hostTime = hostTime
        self.pointX = pointX
        self.pointY = pointY
        self.button = button
    }
}

/// A raw keypress as captured by the input tracker, before normalization.
/// Records only timing and the cursor location at the moment of the press.
public struct RawKey: Equatable, Sendable {
    public var hostTime: Double
    public var pointX: Double
    public var pointY: Double

    public init(hostTime: Double, pointX: Double, pointY: Double) {
        self.hostTime = hostTime
        self.pointX = pointX
        self.pointY = pointY
    }
}

/// Turns raw capture data into normalized `RecordingMetadata`.
///
/// - Timestamps are made relative to `sessionStart` (the first video frame);
///   samples that occur before the first frame are dropped.
/// - Point coordinates are converted to native pixels using `displayScale`,
///   matching the pixel space of `screen`.
public enum MetadataBuilder {
    public static func build(
        fps: Double,
        displayScale: Double,
        screen: ScreenSize,
        sessionStart: Double,
        sessionEnd: Double,
        rawCursor: [RawCursorSample],
        rawClicks: [RawClick],
        rawKeys: [RawKey] = [],
        cursorBaked: Bool = true
    ) -> RecordingMetadata {
        let duration = max(0, sessionEnd - sessionStart)

        let cursor: [CursorSample] = rawCursor.compactMap { sample in
            let t = sample.hostTime - sessionStart
            guard t >= 0 else { return nil }
            return CursorSample(
                t: t,
                position: Point(x: sample.pointX * displayScale, y: sample.pointY * displayScale)
            )
        }

        let clicks: [ClickEvent] = rawClicks.compactMap { click in
            let t = click.hostTime - sessionStart
            guard t >= 0 else { return nil }
            return ClickEvent(
                t: t,
                position: Point(x: click.pointX * displayScale, y: click.pointY * displayScale),
                button: click.button
            )
        }

        let keys: [KeyEvent] = rawKeys.compactMap { key in
            let t = key.hostTime - sessionStart
            guard t >= 0 else { return nil }
            return KeyEvent(
                t: t,
                position: Point(x: key.pointX * displayScale, y: key.pointY * displayScale)
            )
        }

        return RecordingMetadata(
            fps: fps,
            displayScale: displayScale,
            screen: screen,
            duration: duration,
            cursor: cursor.sorted { $0.t < $1.t },
            clicks: clicks.sorted { $0.t < $1.t },
            keys: keys.sorted { $0.t < $1.t },
            cursorBaked: cursorBaked
        )
    }
}
