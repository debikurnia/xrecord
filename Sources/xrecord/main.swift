import Foundation
import ProjectModel
import ZoomPlanner
import CursorSmoother
import Renderer

func printUsage() {
    print("""
    xrecord — lightweight screen recorder with auto-zoom

    USAGE:
      xrecord record [--output <dir>] [--duration <seconds>] [--fps <n>]
      xrecord render <dir> [options]
      xrecord help

    RECORD OPTIONS:
      --output <dir>     Output directory (default: ./recording-<timestamp>)
      --duration <sec>   Auto-stop after N seconds (default: until Ctrl+C)
      --fps <n>          Capture frame rate (default: 60)

    RENDER OPTIONS:
      <dir>              A recording directory (raw.mov + metadata.json)
      --output <file>    Output MP4 path (default: <dir>/output.mp4)
      --zoom <factor>    Auto-zoom level (default: 1.8)
      --background <s>   none | solid:RRGGBB | gradient:RRGGBB,RRGGBB | image:/path
                         (default: neutral slate gradient)
      --padding <frac>   Inset around content, 0..0.45 (default: 0.06; 0 = full-bleed)
      --corner <px>      Corner radius (default: scaled to resolution)
      --shadow <0..1>    Drop-shadow opacity (default: 0.45; 0 = none)
      --cursor-scale <f> Cursor size multiplier (default: 1.5)
      --cursor-smooth <s> Cursor smoothing sigma in seconds (default: 0.08)
      --no-cursor        Don't draw a cursor (cursor-less recordings only)
      --no-click         Disable the click ripple effect
      --motion-blur <v>  Motion-blur strength during fast zoom (default: 0.5; 0 = off)

    Record requires Screen Recording and Accessibility permissions.
    Render needs no special permissions.
    """)
}

func timestampedDirectoryName() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return "recording-\(formatter.string(from: Date()))"
}

func runRecord(_ args: [String]) {
    var outputDir: String?
    var duration: Double?
    var fps: Double = 60

    var i = 0
    while i < args.count {
        switch args[i] {
        case "--output":
            i += 1
            if i < args.count { outputDir = args[i] }
        case "--duration":
            i += 1
            if i < args.count, let value = Double(args[i]) { duration = value }
        case "--fps":
            i += 1
            if i < args.count, let value = Double(args[i]) { fps = value }
        default:
            FileHandle.standardError.write(Data("Ignoring unknown option: \(args[i])\n".utf8))
        }
        i += 1
    }

    let directoryURL = URL(fileURLWithPath: outputDir ?? timestampedDirectoryName())
    do {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    } catch {
        FileHandle.standardError.write(Data("Cannot create output directory: \(error)\n".utf8))
        exit(1)
    }

    let runner = RecordRunner(
        movURL: directoryURL.appendingPathComponent("raw.mov"),
        metaURL: directoryURL.appendingPathComponent("metadata.json"),
        fps: fps
    )
    runner.run(duration: duration)
}

func runRender(_ args: [String]) {
    var directory: String?
    var output: String?
    var zoom: Double = 1.8
    var paddingFraction: Double = 0.06
    var shadowOpacity: Double = 0.45
    var cornerOverride: Double?
    var background: Background = LookConfig.defaultBackground
    var cursorScale: Double = 1.5
    var cursorSmooth: Double = 0.08
    var drawCursor = true
    var clickEffect = true
    var motionBlur: Double = 0.5

    var i = 0
    while i < args.count {
        switch args[i] {
        case "--output", "-o":
            i += 1
            if i < args.count { output = args[i] }
        case "--zoom":
            i += 1
            if i < args.count, let v = Double(args[i]) { zoom = v }
        case "--padding":
            i += 1
            if i < args.count, let v = Double(args[i]) { paddingFraction = v }
        case "--corner":
            i += 1
            if i < args.count, let v = Double(args[i]) { cornerOverride = v }
        case "--shadow":
            i += 1
            if i < args.count, let v = Double(args[i]) { shadowOpacity = v }
        case "--cursor-scale":
            i += 1
            if i < args.count, let v = Double(args[i]) { cursorScale = v }
        case "--cursor-smooth":
            i += 1
            if i < args.count, let v = Double(args[i]) { cursorSmooth = v }
        case "--no-cursor":
            drawCursor = false
        case "--no-click":
            clickEffect = false
        case "--motion-blur":
            i += 1
            if i < args.count, let v = Double(args[i]) { motionBlur = v }
        case "--background", "--bg":
            i += 1
            if i < args.count {
                if let parsed = Background.parse(args[i]) {
                    background = parsed
                } else {
                    FileHandle.standardError.write(Data("Invalid --background spec: \(args[i])\n".utf8))
                    exit(1)
                }
            }
        default:
            if !args[i].hasPrefix("-"), directory == nil {
                directory = args[i]
            } else {
                FileHandle.standardError.write(Data("Ignoring unknown argument: \(args[i])\n".utf8))
            }
        }
        i += 1
    }

    guard let directory else {
        FileHandle.standardError.write(Data("render requires a recording directory.\n".utf8))
        printUsage()
        exit(1)
    }

    let dirURL = URL(fileURLWithPath: directory)
    let movURL = dirURL.appendingPathComponent("raw.mov")
    let metaURL = dirURL.appendingPathComponent("metadata.json")
    let outputURL = URL(fileURLWithPath: output ?? dirURL.appendingPathComponent("output.mp4").path)

    do {
        let data = try Data(contentsOf: metaURL)
        let metadata = try JSONDecoder().decode(RecordingMetadata.self, from: data)

        var zoomConfig = ZoomPlannerConfig()
        zoomConfig.targetScale = zoom
        let planner = ZoomPlanner(config: zoomConfig)
        let timeline = planner.plan(
            clicks: metadata.clicks,
            cursor: metadata.cursor,
            screen: metadata.screen,
            duration: metadata.duration
        )

        // Resolution-aware look defaults derived from the captured width.
        let w = metadata.screen.width
        let look = LookConfig(
            background: background,
            paddingFraction: paddingFraction,
            cornerRadius: cornerOverride ?? (w * 0.012),
            shadowOpacity: shadowOpacity,
            shadowRadius: w * 0.02,
            shadowOffset: w * 0.006,
            cursorScale: cursorScale,
            clickEffect: clickEffect,
            motionBlur: motionBlur
        )

        // Draw our own cursor only for cursor-less recordings (phase 2).
        var cursor: SmoothedCursor?
        if drawCursor && !metadata.cursorBaked {
            let smoothed = CursorSmoother(sigma: cursorSmooth).smooth(metadata.cursor)
            cursor = SmoothedCursor(samples: smoothed)
        }

        let cursorNote = cursor != nil ? " + drawn cursor" : (metadata.cursorBaked ? " (cursor baked in)" : " (cursor off)")
        print("Planned \(timeline.segments.count) zoom segment(s) from \(metadata.clicks.count) clicks\(cursorNote). Rendering…")

        let renderer = VideoRenderer()
        let frames = try renderer.render(
            inputMov: movURL,
            timeline: timeline,
            cursor: cursor,
            clicks: metadata.clicks,
            fps: metadata.fps,
            look: look,
            outputMP4: outputURL
        )
        print("Wrote \(outputURL.path) (\(frames) frames).")
    } catch {
        FileHandle.standardError.write(Data("Render failed: \(error)\n".utf8))
        exit(1)
    }
}

// MARK: - Entry point

let arguments = Array(CommandLine.arguments.dropFirst())

guard let command = arguments.first else {
    printUsage()
    exit(0)
}

switch command {
case "help", "-h", "--help":
    printUsage()
case "record":
    runRecord(Array(arguments.dropFirst()))
case "render":
    runRender(Array(arguments.dropFirst()))
default:
    FileHandle.standardError.write(Data("Unknown command: \(command)\n".utf8))
    printUsage()
    exit(1)
}
