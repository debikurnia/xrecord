import Foundation
import AVFoundation
import CoreImage
import CoreVideo
import CoreMedia
import CoreGraphics
import Metal
import ProjectModel
import ZoomPlanner
import CursorSmoother

/// Offline renderer: reads raw frames from a `.mov`, applies the auto-zoom
/// timeline, visual "look" (background, padding, rounded corners, shadow),
/// click ripples, a smoothed cursor, and optional motion blur, then writes an
/// H.264 `.mp4` at a constant frame rate.
public final class VideoRenderer {
    public enum RenderError: Error, CustomStringConvertible {
        case noVideoTrack
        case readerInitFailed(String)
        case noFrames
        case pixelBufferPoolUnavailable
        case readFailed(String)
        case writeFailed(String)

        public var description: String {
            switch self {
            case .noVideoTrack: return "Input has no video track."
            case .readerInitFailed(let m): return "Could not start reader: \(m)"
            case .noFrames: return "Input produced no frames."
            case .pixelBufferPoolUnavailable: return "Pixel buffer pool unavailable."
            case .readFailed(let m): return "Reading failed: \(m)"
            case .writeFailed(let m): return "Writing failed: \(m)"
            }
        }
    }

    /// Static, per-render precomputed images/transforms plus the timeline and
    /// inputs needed to compose any moment `t`.
    private struct RenderPlan {
        let screen: ScreenSize
        let canvasRect: CGRect
        let contentRectCI: CGRect
        let placeTransform: CGAffineTransform
        let mask: CIImage
        let clear: CIImage
        let backplate: CIImage
        let look: LookConfig
        let timeline: ZoomTimeline
        // Cursor
        let cursor: SmoothedCursor?
        let cursorSprite: CIImage?
        let cursorHotspot: CGPoint
        // Click ripple
        let clicks: [ClickEvent]
        let rippleSprite: CIImage?
        let rippleSpriteRadius: Double
        let rippleR0: Double
        let rippleR1: Double
        let rippleDuration: Double
        let rippleOpacity: Double
    }

    private let ciContext: CIContext
    private let colorSpace = CGColorSpaceCreateDeviceRGB()

    public init() {
        if let device = MTLCreateSystemDefaultDevice() {
            ciContext = CIContext(mtlDevice: device)
        } else {
            ciContext = CIContext()
        }
    }

    /// Renders `inputMov` to `outputMP4` at a constant `fps`, holding the most
    /// recent source frame so the cursor/zoom animate smoothly even when the
    /// screen-capture source has sparse, irregular frames. Returns frames written.
    @discardableResult
    public func render(
        inputMov: URL,
        timeline: ZoomTimeline,
        cursor: SmoothedCursor?,
        clicks: [ClickEvent],
        fps: Double,
        look: LookConfig,
        outputMP4: URL
    ) throws -> Int {
        let screen = timeline.screen
        let width = Int(screen.width)
        let height = Int(screen.height)
        let canvasRect = CGRect(x: 0, y: 0, width: width, height: height)
        let plan = buildPlan(
            screen: screen, canvasRect: canvasRect, look: look,
            timeline: timeline, cursor: cursor, clicks: clicks
        )

        // MARK: Reader
        let asset = AVURLAsset(url: inputMov)
        guard let track = asset.tracks(withMediaType: .video).first else {
            throw RenderError.noVideoTrack
        }
        let sourceDuration = track.timeRange.duration
        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw RenderError.readerInitFailed(error.localizedDescription)
        }
        let readerOutput = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        readerOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(readerOutput) else {
            throw RenderError.readerInitFailed("cannot add track output")
        }
        reader.add(readerOutput)

        // MARK: Writer
        try? FileManager.default.removeItem(at: outputMP4)
        let writer = try AVAssetWriter(outputURL: outputMP4, fileType: .mp4)
        let writerInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
            ]
        )
        writerInput.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
            ]
        )
        guard writer.canAdd(writerInput) else {
            throw RenderError.writeFailed("cannot add writer input")
        }
        writer.add(writerInput)

        guard reader.startReading() else {
            throw RenderError.readerInitFailed(reader.error?.localizedDescription ?? "unknown")
        }
        guard writer.startWriting() else {
            throw RenderError.writeFailed(writer.error?.localizedDescription ?? "unknown")
        }

        // MARK: Constant-frame-rate render loop
        let queue = DispatchQueue(label: "studio.xrecord.render")
        let done = DispatchSemaphore(value: 0)
        var frameCount = 0
        var thrown: Error?

        queue.async {
            defer { done.signal() }

            let fpsInt = max(1, Int(fps.rounded()))
            let timescale = CMTimeScale(fpsInt)
            let dt = 1.0 / Double(fpsInt)
            let totalSeconds = CMTimeGetSeconds(sourceDuration)
            let totalFrames = max(1, Int((totalSeconds * Double(fpsInt)).rounded()))

            guard var currentSample = readerOutput.copyNextSampleBuffer() else {
                thrown = reader.status == .failed
                    ? RenderError.readFailed(reader.error?.localizedDescription ?? "unknown")
                    : RenderError.noFrames
                return
            }
            var nextSample = readerOutput.copyNextSampleBuffer()
            writer.startSession(atSourceTime: .zero)

            func waitUntilReady() {
                while !writerInput.isReadyForMoreMediaData { usleep(500) }
            }

            for k in 0..<totalFrames {
                let outT = Double(k) / Double(fpsInt)

                while let ns = nextSample,
                      CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(ns)) <= outT {
                    currentSample = ns
                    nextSample = readerOutput.copyNextSampleBuffer()
                }

                guard let srcBuffer = CMSampleBufferGetImageBuffer(currentSample) else { continue }
                guard let pool = adaptor.pixelBufferPool else {
                    thrown = RenderError.pixelBufferPoolUnavailable
                    break
                }
                var dst: CVPixelBuffer?
                CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &dst)
                guard let dstBuffer = dst else { continue }

                let frame = self.renderFrame(source: srcBuffer, t: outT, dt: dt, plan: plan)
                self.ciContext.render(frame, to: dstBuffer, bounds: plan.canvasRect, colorSpace: self.colorSpace)

                let pts = CMTime(value: CMTimeValue(k), timescale: timescale)
                guard let sample = self.makeSampleBuffer(
                    pixelBuffer: dstBuffer, pts: pts, duration: CMTime(value: 1, timescale: timescale)
                ) else { continue }
                waitUntilReady()
                if writerInput.append(sample) { frameCount += 1 }
            }

            if reader.status == .failed {
                thrown = RenderError.readFailed(reader.error?.localizedDescription ?? "unknown")
            }
            writer.endSession(atSourceTime: CMTime(seconds: totalSeconds, preferredTimescale: timescale))
            writerInput.markAsFinished()
            let finished = DispatchSemaphore(value: 0)
            writer.finishWriting { finished.signal() }
            finished.wait()
        }

        done.wait()
        if let thrown { throw thrown }
        if writer.status == .failed {
            throw RenderError.writeFailed(writer.error?.localizedDescription ?? "unknown")
        }
        if frameCount == 0 { throw RenderError.noFrames }
        return frameCount
    }

    // MARK: - Frame rendering (with adaptive motion blur)

    private func renderFrame(source: CVImageBuffer, t: Double, dt: Double, plan: RenderPlan) -> CIImage {
        guard plan.look.motionBlur > 0 else {
            return composeAt(source: source, t: t, plan: plan)
        }

        // Estimate motion from the zoom state velocity around this instant.
        let prev = plan.timeline.state(at: max(0, t - dt))
        let next = plan.timeline.state(at: t + dt)
        let scaleVel = abs(next.scale - prev.scale)
        let centerVel = hypot(next.center.x - prev.center.x, next.center.y - prev.center.y) / plan.screen.height
        let motion = scaleVel * 2.0 + centerVel * 4.0

        if motion < 0.004 {
            return composeAt(source: source, t: t, plan: plan)
        }

        // Accumulate sub-frames across an exposure window centered on `t`.
        let maxSamples = 8
        let samples = min(maxSamples, max(2, Int((motion * 40 * plan.look.motionBlur).rounded())))
        let window = dt * (0.6 + plan.look.motionBlur)
        var images: [CIImage] = []
        images.reserveCapacity(samples)
        for j in 0..<samples {
            let tj = t + (Double(j) / Double(samples - 1) - 0.5) * window
            images.append(composeAt(source: source, t: tj, plan: plan))
        }
        return averaged(images)
    }

    /// Averages opaque, canvas-sized frames (motion-blur accumulation) using a
    /// running source-over mean. Blending image i over the accumulator with
    /// weight 1/(i+1) yields the exact average while keeping alpha = 1, so the
    /// result never darkens (a naive RGBA scale + addition dims by 1/K because
    /// Core Image composites in premultiplied alpha).
    private func averaged(_ images: [CIImage]) -> CIImage {
        guard var acc = images.first else { return CIImage.empty() }
        for i in 1..<images.count {
            let weight = 1.0 / Double(i + 1)
            let faded = images[i].applyingFilter("CIColorMatrix", parameters: [
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: weight),
            ])
            acc = faded.applyingFilter("CISourceOverCompositing", parameters: [
                "inputBackgroundImage": acc,
            ])
        }
        return acc
    }

    // MARK: - Composition at a single instant

    private func composeAt(source: CVImageBuffer, t: Double, plan: RenderPlan) -> CIImage {
        let state = plan.timeline.state(at: t)
        let zoomTransform = state.ciTransform(screen: plan.screen)

        let src = CIImage(cvImageBuffer: source)
        let zoomed = src.transformed(by: zoomTransform).cropped(to: plan.canvasRect)
        let placed = zoomed.transformed(by: plan.placeTransform)
        let rounded = placed.applyingFilter("CIBlendWithMask", parameters: [
            "inputBackgroundImage": plan.clear,
            "inputMaskImage": plan.mask,
        ])
        var result = rounded.composited(over: plan.backplate)

        // Click ripples (under the cursor).
        if plan.look.clickEffect, let ripple = plan.rippleSprite, plan.rippleSpriteRadius > 0 {
            let ext = ripple.extent
            for click in plan.clicks {
                let p = (t - click.t) / plan.rippleDuration
                guard p >= 0, p <= 1 else { continue }
                let eased = 1 - (1 - p) * (1 - p)                  // easeOut for radius
                let radius = plan.rippleR0 + (plan.rippleR1 - plan.rippleR0) * eased
                let alpha = sin(p * Double.pi) * plan.rippleOpacity // fade in then out
                guard alpha > 0.001 else { continue }

                let scale = radius / plan.rippleSpriteRadius
                let ciClick = CGPoint(x: click.position.x, y: plan.screen.height - click.position.y)
                let canvas = ciClick.applying(zoomTransform).applying(plan.placeTransform)
                let tx = canvas.x - ext.midX * scale
                let ty = canvas.y - ext.midY * scale
                var sprite = ripple.transformed(by: CGAffineTransform(translationX: tx, y: ty).scaledBy(x: scale, y: scale))
                sprite = sprite.applyingFilter("CIColorMatrix", parameters: [
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: alpha),
                ])
                result = sprite.cropped(to: plan.contentRectCI).composited(over: result)
            }
        }

        // Our own cursor (cursor-less recordings only).
        if let cursor = plan.cursor, let sprite = plan.cursorSprite, let pos = cursor.position(at: t) {
            let ciCursor = CGPoint(x: pos.x, y: plan.screen.height - pos.y)
            let inCanvas = ciCursor.applying(zoomTransform).applying(plan.placeTransform)
            let tx = inCanvas.x - plan.cursorHotspot.x
            let ty = inCanvas.y - plan.cursorHotspot.y
            let placedCursor = sprite
                .transformed(by: CGAffineTransform(translationX: tx, y: ty))
                .cropped(to: plan.contentRectCI)
            result = placedCursor.composited(over: result)
        }

        return result.cropped(to: plan.canvasRect)
    }

    // MARK: - Sample buffer

    private func makeSampleBuffer(pixelBuffer: CVPixelBuffer, pts: CMTime, duration: CMTime) -> CMSampleBuffer? {
        var formatDescription: CMFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        ) == noErr, let format = formatDescription else {
            return nil
        }
        var timing = CMSampleTimingInfo(duration: duration, presentationTimeStamp: pts, decodeTimeStamp: .invalid)
        var sampleBuffer: CMSampleBuffer?
        guard CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: format,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        ) == noErr else {
            return nil
        }
        return sampleBuffer
    }

    // MARK: - Plan construction

    private func buildPlan(
        screen: ScreenSize,
        canvasRect: CGRect,
        look: LookConfig,
        timeline: ZoomTimeline,
        cursor: SmoothedCursor?,
        clicks: [ClickEvent]
    ) -> RenderPlan {
        let layout = contentLayout(canvas: screen, paddingFraction: look.paddingFraction)
        let contentYCI = screen.height - layout.y - layout.height
        let contentRectCI = CGRect(x: layout.x, y: contentYCI, width: layout.width, height: layout.height)
        let scale = layout.width / screen.width

        let placeTransform = CGAffineTransform(translationX: layout.x, y: contentYCI)
            .scaledBy(x: scale, y: scale)

        let mask = roundedRectImage(
            canvasRect: canvasRect, rect: contentRectCI, radius: look.cornerRadius,
            color: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        ) ?? CIImage(color: CIColor(red: 1, green: 1, blue: 1)).cropped(to: canvasRect)

        let clear = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: canvasRect)
        let background = makeBackground(look.background, canvasRect: canvasRect)
        let backplate = makeBackplate(background: background, contentRectCI: contentRectCI, canvasRect: canvasRect, look: look)

        var cursorSprite: CIImage?
        var cursorHotspot = CGPoint.zero
        if cursor != nil, let sprite = makeCursorSprite(screen: screen, scale: look.cursorScale) {
            cursorSprite = sprite.image
            cursorHotspot = sprite.hotspot
        }

        var rippleSprite: CIImage?
        var rippleSpriteRadius = 0.0
        if look.clickEffect, !clicks.isEmpty, let ripple = makeRippleSprite() {
            rippleSprite = ripple.image
            rippleSpriteRadius = ripple.radius
        }

        return RenderPlan(
            screen: screen,
            canvasRect: canvasRect,
            contentRectCI: contentRectCI,
            placeTransform: placeTransform,
            mask: mask,
            clear: clear,
            backplate: backplate,
            look: look,
            timeline: timeline,
            cursor: cursor,
            cursorSprite: cursorSprite,
            cursorHotspot: cursorHotspot,
            clicks: clicks,
            rippleSprite: rippleSprite,
            rippleSpriteRadius: rippleSpriteRadius,
            rippleR0: screen.height * 0.009,
            rippleR1: screen.height * 0.038,
            rippleDuration: 0.45,
            rippleOpacity: 0.5
        )
    }

    // MARK: - Sprites

    /// A high-res ring sprite (white band with dark edges, visible on any
    /// background). Returns the image and the radius it was drawn at.
    private func makeRippleSprite() -> (image: CIImage, radius: Double)? {
        let d = 256
        let pad = 18.0
        let radius = Double(d) / 2 - pad
        guard let context = CGContext(
            data: nil, width: d, height: d, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.clear(CGRect(x: 0, y: 0, width: d, height: d))
        let rect = CGRect(x: Double(d) / 2 - radius, y: Double(d) / 2 - radius, width: radius * 2, height: radius * 2)
        let ringWidth = Double(d) * 0.05
        // Dark outline first (wider), then white band on top.
        context.setStrokeColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.5))
        context.setLineWidth(ringWidth + Double(d) * 0.02)
        context.strokeEllipse(in: rect)
        context.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.setLineWidth(ringWidth)
        context.strokeEllipse(in: rect)
        guard let cgImage = context.makeImage() else { return nil }
        return (CIImage(cgImage: cgImage), radius)
    }

    /// An enlarged arrow-pointer sprite. Returns the image and the tip hotspot
    /// in the sprite's (Core Image, bottom-left origin) local space.
    private func makeCursorSprite(screen: ScreenSize, scale: Double) -> (image: CIImage, hotspot: CGPoint)? {
        let height = screen.height * 0.03 * max(0.1, scale)
        let width = height * 0.62
        let pad = max(1.0, height * 0.05)
        let pxWidth = Int(ceil(width + 2 * pad))
        let pxHeight = Int(ceil(height + 2 * pad))

        guard let context = CGContext(
            data: nil, width: pxWidth, height: pxHeight, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.clear(CGRect(x: 0, y: 0, width: pxWidth, height: pxHeight))

        let sx = width / 12.0
        let sy = height / 19.0
        func p(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: pad + x * sx, y: Double(pxHeight) - pad - y * sy)
        }
        let points = [
            p(0, 0), p(0, 16), p(3.5, 12.5), p(6, 18), p(8.5, 17), p(5.5, 11), p(11.5, 11),
        ]

        context.beginPath()
        context.move(to: points[0])
        for pt in points.dropFirst() { context.addLine(to: pt) }
        context.closePath()
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fillPath()

        context.beginPath()
        context.move(to: points[0])
        for pt in points.dropFirst() { context.addLine(to: pt) }
        context.closePath()
        context.setStrokeColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.9))
        context.setLineWidth(max(1.0, height * 0.045))
        context.setLineJoin(.round)
        context.strokePath()

        guard let cgImage = context.makeImage() else { return nil }
        return (CIImage(cgImage: cgImage), p(0, 0))
    }

    // MARK: - Background / shadow

    private func makeBackground(_ background: Background, canvasRect: CGRect) -> CIImage {
        switch background {
        case .transparent:
            return CIImage(color: CIColor(red: 0, green: 0, blue: 0)).cropped(to: canvasRect)
        case .solid(let r, let g, let b):
            return CIImage(color: CIColor(red: r, green: g, blue: b)).cropped(to: canvasRect)
        case .gradient(let r0, let g0, let b0, let r1, let g1, let b1):
            let filter = CIFilter(name: "CILinearGradient")!
            filter.setValue(CIVector(x: 0, y: canvasRect.height), forKey: "inputPoint0")
            filter.setValue(CIVector(x: canvasRect.width, y: 0), forKey: "inputPoint1")
            filter.setValue(CIColor(red: r0, green: g0, blue: b0), forKey: "inputColor0")
            filter.setValue(CIColor(red: r1, green: g1, blue: b1), forKey: "inputColor1")
            if let out = filter.outputImage {
                return out.cropped(to: canvasRect)
            }
            return CIImage(color: CIColor(red: r0, green: g0, blue: b0)).cropped(to: canvasRect)
        case .image(let url):
            guard let image = CIImage(contentsOf: url) else {
                return CIImage(color: CIColor(red: 0, green: 0, blue: 0)).cropped(to: canvasRect)
            }
            let ext = image.extent
            guard ext.width > 0, ext.height > 0 else { return image.cropped(to: canvasRect) }
            let s = max(canvasRect.width / ext.width, canvasRect.height / ext.height)
            let scaled = image.transformed(by: CGAffineTransform(scaleX: s, y: s))
            let se = scaled.extent
            let tx = (canvasRect.width - se.width) / 2 - se.origin.x
            let ty = (canvasRect.height - se.height) / 2 - se.origin.y
            return scaled.transformed(by: CGAffineTransform(translationX: tx, y: ty)).cropped(to: canvasRect)
        }
    }

    private func makeBackplate(background: CIImage, contentRectCI: CGRect, canvasRect: CGRect, look: LookConfig) -> CIImage {
        guard look.shadowOpacity > 0 else { return background.cropped(to: canvasRect) }
        guard let shadowBase = roundedRectImage(
            canvasRect: canvasRect, rect: contentRectCI, radius: look.cornerRadius,
            color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        ) else { return background.cropped(to: canvasRect) }

        var shadow = shadowBase
        if look.shadowRadius > 0 {
            shadow = shadow.applyingFilter("CIGaussianBlur", parameters: ["inputRadius": look.shadowRadius])
        }
        shadow = shadow.transformed(by: CGAffineTransform(translationX: 0, y: -look.shadowOffset))
        shadow = shadow.applyingFilter("CIColorMatrix", parameters: [
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: look.shadowOpacity),
        ])
        return shadow.composited(over: background).cropped(to: canvasRect)
    }

    private func roundedRectImage(canvasRect: CGRect, rect: CGRect, radius: Double, color: CGColor) -> CIImage? {
        let width = Int(canvasRect.width)
        let height = Int(canvasRect.height)
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.clear(canvasRect)
        let r = max(0, min(radius, min(rect.width, rect.height) / 2))
        let path = CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
        context.addPath(path)
        context.setFillColor(color)
        context.fillPath()
        guard let cgImage = context.makeImage() else { return nil }
        return CIImage(cgImage: cgImage)
    }
}
