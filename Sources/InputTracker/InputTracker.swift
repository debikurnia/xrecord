import Foundation
import CoreGraphics
import QuartzCore
import ProjectModel

/// Captures global cursor movement and mouse clicks via a listen-only
/// `CGEventTap`. Events are timestamped with `CACurrentMediaTime()` (the host
/// clock, shared with ScreenCaptureKit frame timestamps).
///
/// Requires Accessibility / Input Monitoring permission. The tap is installed
/// on the main run loop, so the caller must run the main run loop.
public final class InputTracker {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let lock = NSLock()
    private var cursorSamples: [RawCursorSample] = []
    private var clickEvents: [RawClick] = []
    private var keyEvents: [RawKey] = []

    public init() {}

    /// Installs the event tap on the main run loop. Returns false if the tap
    /// could not be created (typically missing permission).
    @discardableResult
    public func start() -> Bool {
        let mask: CGEventMask =
            (1 << CGEventType.mouseMoved.rawValue) |
            (1 << CGEventType.leftMouseDragged.rawValue) |
            (1 << CGEventType.rightMouseDragged.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.keyDown.rawValue)

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                if let refcon {
                    let tracker = Unmanaged<InputTracker>.fromOpaque(refcon).takeUnretainedValue()
                    tracker.handle(type: type, event: event)
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        ) else {
            return false
        }

        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    public func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    /// A thread-safe copy of everything captured so far.
    public func snapshot() -> (cursor: [RawCursorSample], clicks: [RawClick], keys: [RawKey]) {
        lock.lock()
        defer { lock.unlock() }
        return (cursorSamples, clickEvents, keyEvents)
    }

    private func handle(type: CGEventType, event: CGEvent) {
        let loc = event.location // global, points, top-left origin
        let t = CACurrentMediaTime()

        lock.lock()
        defer { lock.unlock() }

        switch type {
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged:
            cursorSamples.append(RawCursorSample(hostTime: t, pointX: Double(loc.x), pointY: Double(loc.y)))
        case .leftMouseDown:
            clickEvents.append(RawClick(hostTime: t, pointX: Double(loc.x), pointY: Double(loc.y), button: .left))
        case .rightMouseDown:
            clickEvents.append(RawClick(hostTime: t, pointX: Double(loc.x), pointY: Double(loc.y), button: .right))
        case .keyDown:
            // Record only that a key was pressed and where the cursor was.
            // The key code / character is deliberately never read.
            keyEvents.append(RawKey(hostTime: t, pointX: Double(loc.x), pointY: Double(loc.y)))
        default:
            break
        }
    }
}
