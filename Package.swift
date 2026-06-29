// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "xrecord",
    platforms: [
        .macOS(.v13) // ScreenCaptureKit + system audio require macOS 13+
    ],
    products: [
        .library(name: "ProjectModel", targets: ["ProjectModel"]),
        .library(name: "ZoomPlanner", targets: ["ZoomPlanner"]),
        .executable(name: "xrecord", targets: ["xrecord"]),
    ],
    targets: [
        // Shared data types (cursor track, clicks, recording metadata, geometry).
        .target(
            name: "ProjectModel"
        ),
        // Pure auto-zoom algorithm: clustering, segment generation, anti-jitter
        // merge, cursor-follow, and zoom(t) evaluation. No screen access.
        .target(
            name: "ZoomPlanner",
            dependencies: ["ProjectModel"]
        ),
        // Pure cursor smoothing + time-queryable smoothed track.
        .target(
            name: "CursorSmoother",
            dependencies: ["ProjectModel"]
        ),
        // ScreenCaptureKit wrapper that writes raw HEVC frames to a .mov file.
        // Uses Swift 5 language mode to keep the system/AVFoundation glue free
        // of strict-concurrency churn.
        .target(
            name: "CaptureKit",
            dependencies: ["ProjectModel"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // CGEventTap-based cursor/click capture.
        .target(
            name: "InputTracker",
            dependencies: ["ProjectModel"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Offline render: applies the zoom timeline to raw frames -> MP4.
        .target(
            name: "Renderer",
            dependencies: ["ProjectModel", "ZoomPlanner", "CursorSmoother"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // The command-line entry point: `xrecord record` / `xrecord render`.
        .executableTarget(
            name: "xrecord",
            dependencies: ["ProjectModel", "ZoomPlanner", "CursorSmoother", "CaptureKit", "InputTracker", "Renderer"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "ZoomPlannerTests",
            dependencies: ["ZoomPlanner", "ProjectModel", "Renderer", "CursorSmoother"]
        ),
    ]
)
