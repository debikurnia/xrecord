<div align="center">

# XRecord

Lightweight screen recording for macOS with automatic zoom.
An open-source, native alternative to Screen Studio.

<br/>

![macOS](https://img.shields.io/badge/macOS-13+-000000?style=for-the-badge&logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-6-F05138?style=for-the-badge&logo=swift&logoColor=white)
![ScreenCaptureKit](https://img.shields.io/badge/ScreenCaptureKit-native-7C3AED?style=for-the-badge)
[![License: MIT](https://img.shields.io/badge/license-MIT-22C55E?style=for-the-badge)](LICENSE)
![Tests](https://img.shields.io/badge/tests-41%20passing-22C55E?style=for-the-badge)
[![Made by Debi Kurnia](https://img.shields.io/badge/made%20by-Debi%20Kurnia-7C3AED?style=for-the-badge)](https://debikurnia.id)

</div>

---

## Overview

XRecord records your screen with Apple's ScreenCaptureKit and renders an edited
MP4 entirely on your machine. It tracks your clicks and cursor, then zooms and
pans to follow the action with smooth easing, the effect popularized by paid
tools like Screen Studio.

The binary is small (about 0.5 MB) with no runtime dependencies. The zoom is
computed deterministically from your input rather than by a model, so the same
recording always renders the same way. Nothing is uploaded; capture and render
both run locally.

## Features

- Automatic zoom that follows your clicks, with clustering and smooth panning between targets.
- Native capture through ScreenCaptureKit, encoded to HEVC.
- Styled output: gradient, solid, or image background, with padding, rounded corners, and a drop shadow.
- A cursor that is drawn separately, smoothed, and enlarged, rather than baked into the recording.
- A ripple effect on each click.
- Adaptive motion blur during fast zooms.
- Constant 60 fps output with accurate duration, even when the source frames are sparse.
- Fully local. Your screen and input never leave your Mac.

## Requirements

macOS 13 or later, on Apple Silicon or Intel. A Swift 6 toolchain is required;
the Xcode Command Line Tools are enough, full Xcode is not needed.

## Getting started

```bash
git clone https://github.com/debikurnia/xrecord.git
cd xrecord
make build          # or: swift build -c release

# record until you press Ctrl+C (or pass --duration)
./.build/release/xrecord record --duration 30

# render the recording into output.mp4
./.build/release/xrecord render recording-<timestamp>
```

On the first run, macOS asks for Screen Recording and Accessibility permission
for your terminal (System Settings, then Privacy and Security).

## Usage

```
xrecord record  [--output <dir>] [--duration <seconds>] [--fps <n>]
xrecord render  <dir> [options]
xrecord help
```

Render options:

| Flag | Default | Description |
|------|---------|-------------|
| `--zoom <factor>` | `1.8` | Auto-zoom level |
| `--background <spec>` | slate gradient | Background style (see below) |
| `--padding <frac>` | `0.06` | Inset around content (`0` is full-bleed) |
| `--corner <px>` | auto | Corner radius |
| `--shadow <0..1>` | `0.45` | Drop-shadow opacity |
| `--cursor-scale <f>` | `1.5` | Cursor size multiplier |
| `--cursor-smooth <s>` | `0.08` | Cursor smoothing in seconds |
| `--motion-blur <0..1>` | `0.5` | Motion-blur strength (`0` is off) |
| `--no-cursor` | | Do not draw the cursor |
| `--no-click` | | Disable the click ripple |

The `--background` value accepts one of:

```
none
solid:RRGGBB
gradient:RRGGBB,RRGGBB
image:/path/to/file
```

Example:

```bash
xrecord render recording-xxxx --zoom 2.2 --background solid:101216 --cursor-scale 2
```

## How it works

```
RECORD                                      RENDER
ScreenCaptureKit -> raw.mov (HEVC)          read frames at a constant 60 fps
CGEventTap       -> metadata.json     -->   apply zoom, look, and cursor      --> output.mp4
  (cursor track + clicks)                   add ripple and motion blur (Core Image)

                         ZoomPlanner: clicks -> zoom timeline (pure, unit-tested)
```

Recording is offline-first: capture writes raw frames plus a metadata sidecar,
and the renderer replays them at a steady frame rate. The cursor and zoom stay
smooth even when the screen was static during capture.

## Architecture

| Module | Responsibility |
|--------|----------------|
| `ProjectModel` | Shared types: geometry, recording metadata, frame layout |
| `ZoomPlanner` | Auto-zoom algorithm and zoom-to-transform math (pure, unit-tested) |
| `CursorSmoother` | Zero-phase cursor smoothing (pure, unit-tested) |
| `CaptureKit` | ScreenCaptureKit capture to an HEVC `.mov` |
| `InputTracker` | CGEventTap cursor and click capture |
| `Renderer` | Core Image pipeline to an H.264 MP4 |
| `xrecord` | Command-line entry point |

## Tests

```bash
make test     # 41 tests across 6 suites (Swift Testing)
```

## Roadmap

- GIF export
- Webcam overlay (picture-in-picture)
- Manual zoom keyframes
- SwiftUI timeline editor

## License

Released under the MIT License. See [LICENSE](LICENSE) for details.

---

<div align="center">

Built by Debi Kurnia

[![Website](https://img.shields.io/badge/Website-debikurnia.id-7C3AED?style=for-the-badge&logo=safari&logoColor=white)](https://debikurnia.id)
[![Opustock](https://img.shields.io/badge/Opustock-AI%20tools-111827?style=for-the-badge)](https://opustock.com)
[![LinkedIn](https://img.shields.io/badge/LinkedIn-debikurnia-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/debikurnia)

</div>
