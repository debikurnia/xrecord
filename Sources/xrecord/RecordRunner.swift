import Foundation
import CoreFoundation
import QuartzCore
import CaptureKit
import InputTracker
import ProjectModel

/// Coordinates a single `xrecord record` session: starts screen capture and
/// input tracking, waits for a stop trigger (Ctrl+C or a duration), then
/// finalizes the video and writes `metadata.json`.
final class RecordRunner {
    private let recorder: ScreenRecorder
    private let tracker: InputTracker
    private let movURL: URL
    private let metaURL: URL

    private var captureInfo: ScreenRecorder.Info?
    private var signalSource: DispatchSourceSignal?
    private var didStop = false
    private var stopTime: Double = 0

    init(movURL: URL, metaURL: URL, fps: Double) {
        self.movURL = movURL
        self.metaURL = metaURL
        self.recorder = ScreenRecorder(outputURL: movURL, fps: fps)
        self.tracker = InputTracker()
    }

    /// Runs the session, blocking on the main run loop until stopped.
    func run(duration: Double?) {
        Task {
            do {
                let info = try await recorder.start()
                self.captureInfo = info
                print("Recording \(info.width)x\(info.height) @ \(Int(info.fps))fps — press Ctrl+C to stop.")
            } catch {
                self.fail("Failed to start screen capture: \(error.localizedDescription). " +
                          "Grant Screen Recording permission to your terminal in System Settings → Privacy & Security.")
            }
        }

        if !tracker.start() {
            let warning = "Warning: could not start input tracking. Grant Accessibility/Input " +
                "Monitoring permission to your terminal; zoom metadata will be empty otherwise.\n"
            FileHandle.standardError.write(Data(warning.utf8))
        }

        installSignalHandler()

        if let duration {
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
                self?.stop()
            }
        }

        CFRunLoopRun()
    }

    private func installSignalHandler() {
        signal(SIGINT, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        source.setEventHandler { [weak self] in
            print("\nStopping…")
            self?.stop()
        }
        source.resume()
        signalSource = source
    }

    private func stop() {
        if didStop { return }
        didStop = true
        stopTime = CACurrentMediaTime()
        tracker.stop()

        Task {
            do {
                try await recorder.stop()
            } catch {
                FileHandle.standardError.write(Data("Error finalizing video: \(error)\n".utf8))
            }
            self.writeMetadata()
            DispatchQueue.main.async {
                CFRunLoopStop(CFRunLoopGetMain())
            }
        }
    }

    private func fail(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        DispatchQueue.main.async {
            CFRunLoopStop(CFRunLoopGetMain())
        }
    }

    private func writeMetadata() {
        guard let info = captureInfo else { return }
        let sessionStart = recorder.firstFrameTime
        guard sessionStart > 0 else {
            FileHandle.standardError.write(Data("No frames were captured; metadata not written.\n".utf8))
            return
        }

        let raw = tracker.snapshot()
        let metadata = MetadataBuilder.build(
            fps: info.fps,
            displayScale: info.scale,
            screen: ScreenSize(width: Double(info.width), height: Double(info.height)),
            sessionStart: sessionStart,
            sessionEnd: stopTime,
            rawCursor: raw.cursor,
            rawClicks: raw.clicks,
            cursorBaked: info.cursorBaked
        )

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(metadata)
            try data.write(to: metaURL)
            print(String(
                format: "Saved %@ and %@ — %.1fs, %d clicks, %d cursor samples.",
                movURL.path, metaURL.path, metadata.duration, metadata.clicks.count, metadata.cursor.count
            ))
        } catch {
            FileHandle.standardError.write(Data("Failed to write metadata: \(error)\n".utf8))
        }
    }
}
