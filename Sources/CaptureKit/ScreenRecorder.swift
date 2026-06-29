import Foundation
import ScreenCaptureKit
import AVFoundation
import CoreMedia
import CoreVideo
import AppKit
import ProjectModel

/// Captures the main display with ScreenCaptureKit and writes raw HEVC frames
/// to a `.mov` file via `AVAssetWriter`. Phase 1: the real system cursor is
/// baked into the video; cursor positions (captured separately) only drive zoom.
public final class ScreenRecorder: NSObject, SCStreamOutput, SCStreamDelegate {
    /// Properties of the actual capture, known after `start()`.
    public struct Info: Sendable {
        public var width: Int
        public var height: Int
        public var scale: Double
        public var fps: Double
        /// Whether the system cursor is baked into the recorded frames.
        public var cursorBaked: Bool
    }

    public enum RecorderError: Error {
        case noDisplay
        case cannotAddInput
    }

    private let outputURL: URL
    private let fps: Double
    private let sampleQueue = DispatchQueue(label: "studio.xrecord.capture")

    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?

    private let stateLock = NSLock()
    private var sessionStarted = false

    /// Presentation time (seconds, host clock) of the first written frame.
    public private(set) var firstFrameTime: Double = 0
    public private(set) var info: Info?

    public init(outputURL: URL, fps: Double = 60) {
        self.outputURL = outputURL
        self.fps = fps
        super.init()
    }

    public func start() async throws -> Info {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true
        )
        guard let display = content.displays.first else {
            throw RecorderError.noDisplay
        }

        let scale = Self.scale(for: display.displayID)
        let pxWidth = Int(Double(display.width) * scale)
        let pxHeight = Int(Double(display.height) * scale)

        let config = SCStreamConfiguration()
        config.width = pxWidth
        config.height = pxHeight
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false // phase 2: cursor drawn by the renderer
        config.queueDepth = 6

        let filter = SCContentFilter(display: display, excludingWindows: [])

        try setupWriter(width: pxWidth, height: pxHeight)

        let info = Info(
            width: pxWidth,
            height: pxHeight,
            scale: scale,
            fps: fps,
            cursorBaked: config.showsCursor
        )
        self.info = info

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        self.stream = stream
        try await stream.startCapture()

        return info
    }

    public func stop() async throws {
        if let stream {
            try await stream.stopCapture()
        }
        self.stream = nil

        videoInput?.markAsFinished()
        if let writer, writer.status == .writing {
            await writer.finishWriting()
        }
    }

    private func setupWriter(width: Int, height: Int) throws {
        try? FileManager.default.removeItem(at: outputURL)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true

        guard writer.canAdd(input) else { throw RecorderError.cannotAddInput }
        writer.add(input)

        self.writer = writer
        self.videoInput = input
    }

    // MARK: - SCStreamOutput

    public func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .screen, CMSampleBufferDataIsReady(sampleBuffer) else { return }

        // Only write frames the window server marked complete.
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
            as? [[SCStreamFrameInfo: Any]],
            let statusRaw = attachments.first?[.status] as? Int,
            let status = SCFrameStatus(rawValue: statusRaw),
            status != .complete {
            return
        }

        guard let writer, let videoInput else { return }

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        stateLock.lock()
        if !sessionStarted {
            sessionStarted = true
            firstFrameTime = CMTimeGetSeconds(pts)
            writer.startWriting()
            writer.startSession(atSourceTime: pts)
        }
        stateLock.unlock()

        if videoInput.isReadyForMoreMediaData {
            videoInput.append(sampleBuffer)
        }
    }

    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        FileHandle.standardError.write(Data("Capture stopped with error: \(error)\n".utf8))
    }

    // MARK: - Helpers

    private static func scale(for displayID: CGDirectDisplayID) -> Double {
        for screen in NSScreen.screens {
            if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
               number.uint32Value == displayID {
                return Double(screen.backingScaleFactor)
            }
        }
        return Double(NSScreen.main?.backingScaleFactor ?? 2.0)
    }
}
