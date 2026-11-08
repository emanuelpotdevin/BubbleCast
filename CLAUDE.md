# BubbleCast

A native macOS screen recorder (Swift, AppKit, ScreenCaptureKit) with a floating webcam bubble and
one-click modes: Screen + Cam, Screen only, Camera only. No Xcode project; `build.sh` compiles with `swiftc`
(`UNIVERSAL=1 ./build.sh` for Apple silicon + Intel). GitHub Actions (`.github/workflows/build.yml`) builds every push
and attaches `BubbleCast-macOS.zip` to releases for `v*` tags.

## When the user asks to build / install / set it up

Follow **[SETUP_FOR_AI.md](SETUP_FOR_AI.md)** step by step (requirements check, build, install, permissions, verify).

## Layout

- `Sources/main.swift` – app controller: modes, recording state, countdown, hotkeys, settings menu
- `Sources/Recorder.swift` – ScreenCaptureKit + SCRecordingOutput → `~/Movies/BubbleCast/*.mov` (HEVC, mic, optional system audio). Pause = close the current
  temp segment; Stop = join segments with AVMutableComposition + passthrough export
- `Sources/Bubble.swift` – the round webcam window; goes full screen for Camera-only mode
- `Sources/Camera.swift` – AVCaptureSession for the webcam, permission alert helper
- `Sources/ControlBar.swift` – floating toolbar (excluded from the recording)
- `Sources/HotKeys.swift` – global shortcuts (⌥⌘R record, ⌥⌘P pause, ⌥⌘B bubble, ⌥⌘1/2/3 modes)

Key design point: the bubble is an ordinary on-screen window, so the screen recording captures it; switching to
Camera-only just makes that window full screen. That is why modes can switch mid-recording in one file.

## Testing

`open -W -n --stdout out.txt /Applications/BubbleCast.app --args --selftest` records 2s, pauses, records 2s more,
saves, prints `SELFTEST url=… bytes=…` and quits (exit 0 on success). Needs Screen Recording permission.
