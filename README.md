# BubbleCast

**A free, native screen recorder for Mac with a webcam bubble.**

Record your screen with your face in a round bubble, and switch with one click between
**Screen + Cam**, **Screen only** and **Camera only** — even in the middle of a recording.

[![Build](https://github.com/emanuelpotdevin/BubbleCast/actions/workflows/build.yml/badge.svg)](https://github.com/emanuelpotdevin/BubbleCast/actions/workflows/build.yml)

## Features

- 🎥 Webcam bubble you can drag, resize, and turn on/off
- 🔀 One-click modes: Screen + Cam · Screen only · Camera only (switch live while recording)
- ⏸️ Pause / resume — paused time is left out of the video
- 🎙️ Microphone and Mac system audio
- ⌨️ Shortcuts that work from any app
- 🖥️ Full Retina resolution, 60 fps, HEVC — saved to `~/Movies/BubbleCast/`
- 🪶 Native Swift app, no dependencies, no account, nothing uploaded anywhere

Requires **macOS 15 (Sequoia) or newer**. Works on Apple silicon and Intel Macs.

## Install

### Option 1 — Let your AI assistant do it (recommended)

1. Download this repo: **Code → Download ZIP** (or `git clone https://github.com/emanuelpotdevin/BubbleCast.git`) and unzip it.
2. Open the folder in **Claude Code** (or Cursor, Codex, …).
3. Say: **"Set up BubbleCast for me following SETUP_FOR_AI.md."**

The assistant checks your Mac, builds the app, installs it in Applications, and walks you through the permissions.
The full step-by-step guide it follows is in **[SETUP_FOR_AI.md](SETUP_FOR_AI.md)**.

### Option 2 — Download the ready-made app

1. Download **[BubbleCast-macOS.zip](https://github.com/emanuelpotdevin/BubbleCast/releases/latest/download/BubbleCast-macOS.zip)** from the latest release.
2. Unzip and drag **BubbleCast.app** into **Applications**.
3. The app is not notarized by Apple, so the first launch is blocked: open
   **System Settings → Privacy & Security**, scroll down, click **Open Anyway**.

### Option 3 — Build it yourself

Needs Apple's command line tools (`xcode-select --install`).

```bash
git clone https://github.com/emanuelpotdevin/BubbleCast.git
cd BubbleCast
./build.sh
ditto build/BubbleCast.app /Applications/BubbleCast.app
open /Applications/BubbleCast.app
```

On first use, allow **Camera**, **Microphone** and **Screen Recording**, then quit and reopen the app once.

## How to use

| Control | What it does |
|---|---|
| **Record** | 3-2-1 countdown, then becomes **Stop** with a timer. Stop saves and shows the video in Finder. |
| **Pause / Resume** | Appears while recording. Paused time is not in the video. |
| **Screen + Cam / Screen / Camera** | Switch layout instantly, even while recording. |
| **Bubble** button | Webcam bubble on/off. Drag to move, double-click to resize. |
| **Mic / speaker** | Record your voice / your Mac's sound (set before recording). |
| **⋯** | Choose camera, microphone, bubble size, open recordings folder, quit. |

**Shortcuts:** ⌥⌘R record/stop · ⌥⌘P pause/resume · ⌥⌘B bubble · ⌥⌘1 Screen + Cam · ⌥⌘2 Screen · ⌥⌘3 Camera

## How it works

BubbleCast uses Apple's ScreenCaptureKit to record the display. The webcam bubble is a normal floating
window, so it is captured as part of the screen; "Camera only" simply makes that window full screen.
That's why modes can switch mid-recording into a single file. The toolbar itself is excluded from the video.

## License

[MIT](LICENSE)
