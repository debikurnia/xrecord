<div align="center">

# 🎬 XRecord

### Beautiful, lightweight screen recordings on macOS — with automatic zoom.

A **native, open-source** take on Screen Studio. No Electron. No subscription.
You record; XRecord turns it into a polished demo with auto‑zoom, a styled
background, a smooth cursor, and motion blur.

<br/>

![macOS](https://img.shields.io/badge/macOS-13%2B-000000?style=for-the-badge&logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-6-F05138?style=for-the-badge&logo=swift&logoColor=white)
![ScreenCaptureKit](https://img.shields.io/badge/ScreenCaptureKit-native-7C3AED?style=for-the-badge)
![Tests](https://img.shields.io/badge/tests-41%20passing-22C55E?style=for-the-badge)
[![Made by Debi Kurnia](https://img.shields.io/badge/made%20by-Debi%20Kurnia-7C3AED?style=for-the-badge)](https://debikurnia.id)

</div>

---

## Why XRecord?

Screen recordings are more engaging when the view zooms in on what you're doing.
Tools like Screen Studio do this beautifully — but they're heavy and paid.
**XRecord is a tiny native binary** (~0.5 MB) that records with Apple's
`ScreenCaptureKit` and renders an edited MP4 entirely on your machine. Nothing
is uploaded, ever.

The zoom is **automatic and deterministic** (no AI): it watches your clicks and
cursor, clusters them, and pans/zooms with smooth easing.

## ✨ Features

- **Auto‑zoom** around your clicks — clustering, smooth pan between targets, anti‑jitter.
- **Native capture** via `ScreenCaptureKit` → HEVC, light on CPU and disk.
- **The "look"** — gradient / solid / image background, padding, rounded corners, drop shadow.
- **Smooth, enlarged cursor** — drawn (not baked), with zero‑lag smoothing.
- **Click ripple** effect on every click.
- **Motion blur** during fast zooms (adaptive, subtle).
- **Constant 60 fps** output with accurate duration, even when the source is sparse.
- **100% local** — your screen and input never leave your Mac.

## 🚀 Quick start

```bash
git clone https://github.com/debikurnia/xrecord.git
cd xrecord
make build          # or: swift build -c release

# record until you press Ctrl+C (or use --duration)
./.build/release/xrecord record --duration 30

# render the recording into output.mp4
./.build/release/xrecord render recording-<timestamp>
```

> First run will ask for **Screen Recording** and **Accessibility** permissions
> for your terminal (System Settings → Privacy & Security).

## 🕹️ Usage

```
xrecord record  [--output <dir>] [--duration <seconds>] [--fps <n>]
xrecord render  <dir> [options]
xrecord help
```

**Render options**

| Flag | Default | Description |
|------|---------|-------------|
| `--zoom <factor>` | `1.8` | Auto‑zoom level |
| `--background <spec>` | slate gradient | `none` · `solid:RRGGBB` · `gradient:RRGGBB,RRGGBB` · `image:/path` |
| `--padding <frac>` | `0.06` | Inset around content (`0` = full‑bleed) |
| `--corner <px>` | auto | Corner radius |
| `--shadow <0..1>` | `0.45` | Drop‑shadow opacity |
| `--cursor-scale <f>` | `1.5` | Cursor size multiplier |
| `--cursor-smooth <s>` | `0.08` | Cursor smoothing (seconds) |
| `--motion-blur <0..1>` | `0.5` | Motion‑blur strength (`0` = off) |
| `--no-cursor` / `--no-click` | — | Disable drawn cursor / click ripple |

```bash
# example: punchier zoom, dark solid background, bigger cursor
xrecord render recording-xxxx --zoom 2.2 --background solid:101216 --cursor-scale 2
```

## 🔬 How it works

```
┌─ RECORD ───────────────────────────┐     ┌─ RENDER ─────────────────────────┐
│ ScreenCaptureKit ─► raw.mov (HEVC)  │     │ read frames @ constant 60fps      │
│ CGEventTap       ─► metadata.json   │ ──► │ + auto-zoom + look + cursor       │ ─► output.mp4
│   (cursor track + clicks)           │     │ + ripple + motion blur (CoreImage)│
└──────────────────────────────────────┘     └────────────────────────────────────┘
                                                       ▲
                              ZoomPlanner (clicks → zoom timeline, pure & tested)
```

Recording is **offline‑first**: capture produces raw frames plus a metadata
sidecar; the renderer replays it at a steady frame rate, so the cursor and zoom
stay buttery even when the screen was static.

## 🧱 Architecture

| Module | Responsibility |
|--------|----------------|
| `ProjectModel` | Shared types: geometry, recording metadata, frame layout |
| `ZoomPlanner` | Auto‑zoom algorithm + zoom→transform math (pure, unit‑tested) |
| `CursorSmoother` | Zero‑phase cursor smoothing (pure, unit‑tested) |
| `CaptureKit` | `ScreenCaptureKit` → HEVC `.mov` |
| `InputTracker` | `CGEventTap` cursor & click capture |
| `Renderer` | Core Image pipeline → H.264 MP4 |
| `xrecord` | Command‑line entry point |

## ✅ Tests

```bash
make test     # 41 tests across 6 suites (Swift Testing)
```

## 🗺️ Roadmap

- [ ] GIF export
- [ ] Webcam overlay (picture‑in‑picture)
- [ ] Manual zoom keyframes
- [ ] SwiftUI timeline editor

## 📋 Requirements

macOS 13+ (Apple Silicon or Intel) · Swift 6 toolchain (Xcode Command Line Tools).

---

<div align="center">

Built by **Debi Kurnia**

[![Website](https://img.shields.io/badge/Website-debikurnia.id-7C3AED?style=for-the-badge&logo=safari&logoColor=white)](https://debikurnia.id)
[![Opustock](https://img.shields.io/badge/Opustock-AI%20tools-111827?style=for-the-badge)](https://opustock.com)
[![LinkedIn](https://img.shields.io/badge/LinkedIn-debikurnia-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/debikurnia)

</div>
