# BubbleCast — setup guide for AI assistants

You are an AI coding assistant (Claude Code, Cursor, Codex, Copilot, …) helping a person install
**BubbleCast**, a free screen recorder for Mac, after they downloaded or cloned this repository.
Follow these steps in order. Run the commands yourself where you can; where a step needs the person
(a password, a permission dialog, a click), tell them exactly what to do and wait for them.

Talk to the person in plain language. They may not be technical.

---

## Step 1 — Check the Mac

```bash
sw_vers -productVersion
uname -m
```

- The macOS version must be **15.0 or newer**. If it is older, stop and tell the person BubbleCast needs
  macOS 15 (Sequoia) or later.
- `arm64` = Apple silicon, `x86_64` = Intel. Both work.

## Step 2 — Check the Swift compiler

```bash
xcode-select -p && swift --version
```

- If both print something, continue.
- If not, the person needs Apple's free Command Line Tools. Ask them to run this **themselves** (it opens
  an installer window and may ask for their password):

  ```bash
  xcode-select --install
  ```

  Wait until they say it has finished (it can take 5–15 minutes), then run Step 2 again.

## Step 3 — Go to the project folder

Make sure your working directory is the folder that contains `build.sh`, `Sources/` and this file.

```bash
ls build.sh Sources/main.swift
```

If they downloaded the ZIP from GitHub, the folder is usually `~/Downloads/BubbleCast-main`.
If they have not downloaded it yet:

```bash
git clone https://github.com/emanuelpotdevin/BubbleCast.git && cd BubbleCast
```

## Step 4 — Build

```bash
chmod +x build.sh
./build.sh
```

Success ends with `Built build/BubbleCast.app`. It takes about a minute. Warnings are fine; only lines
containing `error:` matter. If you see errors, read the Troubleshooting section below.

## Step 5 — Install into Applications

```bash
pkill -x BubbleCast 2>/dev/null; sleep 1
ditto build/BubbleCast.app /Applications/BubbleCast.app
open /Applications/BubbleCast.app
```

A floating toolbar appears at the bottom of the screen and a round webcam bubble at the bottom left.

## Step 6 — Permissions (the person does this)

Tell the person, step by step:

1. **Camera** and **Microphone**: macOS shows a popup — click **Allow**.
2. Click the red **Record** button once. macOS asks for **Screen & System Audio Recording** permission.
   Click **Open System Settings**, switch **BubbleCast** on, and confirm.
3. **Quit BubbleCast** (⌘Q, or ⋯ menu → Quit) and open it again from Applications. This restart is
   required by macOS after granting screen recording.

Note: the build is signed "ad-hoc" unless the person has an Apple Development certificate, so macOS may
ask for these permissions again after a **re**build. That is normal.

## Step 7 — Verify (optional, recommended)

After permissions are granted, you can test recording without any clicks:

```bash
open -W -n --stdout /tmp/bubblecast-test.txt /Applications/BubbleCast.app --args --selftest
cat /tmp/bubblecast-test.txt
```

It records ~4 seconds (with a pause in the middle) and quits. Success looks like
`SELFTEST url=/Users/…/Movies/BubbleCast/BubbleCast ….mov bytes=<a number above 0> error=none`.
Delete that test video afterwards if the person does not want it. Then reopen the app:
`open /Applications/BubbleCast.app`.

## Step 8 — Show the person how to use it

- **Record** → 3-2-1 countdown, then it becomes **Stop** with a timer. Stop saves and opens the video in Finder.
- **Pause / Resume** appears while recording. Paused time is left out of the video.
- **Screen + Cam / Screen / Camera** switch the layout with one click, even while recording.
- **Bubble** button turns the webcam bubble on/off. Drag the bubble to move it, double-click to resize.
- **Mic / speaker** buttons choose whether their voice and the Mac's sound are recorded.
- **⋯** menu: choose camera, microphone, bubble size, open the recordings folder, quit.
- Shortcuts from any app: ⌥⌘R record/stop · ⌥⌘P pause · ⌥⌘B bubble · ⌥⌘1 / ⌥⌘2 / ⌥⌘3 modes.
- Videos are saved in `~/Movies/BubbleCast/`.

Suggest they keep it in the Dock: right-click the Dock icon → Options → Keep in Dock.

---

## Alternative — the person only wants the ready-made app (no building)

Download: `https://github.com/emanuelpotdevin/BubbleCast/releases/latest/download/BubbleCast-macOS.zip`

1. Unzip it and drag **BubbleCast.app** into **Applications**.
2. The app is not notarized by Apple, so the first launch is blocked. The person opens
   **System Settings → Privacy & Security**, scrolls down to the message about BubbleCast, clicks
   **Open Anyway**, and confirms.
3. Continue with Step 6.

Building from source (Steps 1–5) avoids that warning, so prefer it when you can run commands.

## Troubleshooting

| Problem | What to do |
|---|---|
| `xcrun: error: invalid active developer path` | Command Line Tools missing → Step 2. |
| `error: … is only available in macOS 15.0 or newer` | Tools are too old. Ask the person to update macOS / Xcode Command Line Tools (Software Update). |
| `Permission denied` running `./build.sh` | `chmod +x build.sh` |
| Clicking Record shows "Screen Recording access is needed" | Step 6.2, then quit and reopen the app. |
| Permission is on but recording still fails | In System Settings → Screen Recording, remove BubbleCast (–), reopen the app, allow again. |
| No webcam image / black bubble | Camera permission (System Settings → Privacy & Security → Camera). Pick the camera in the ⋯ menu. |
| No sound in the video | Mic button must be green **before** pressing Record; check Microphone permission. |
| "BubbleCast can't be opened" after downloading | See the Alternative section (Open Anyway). |

## For developers

- Plain Swift + AppKit, no Xcode project, no dependencies. `build.sh` compiles `Sources/*.swift` with `swiftc`.
- `UNIVERSAL=1 ./build.sh` builds one app for Apple silicon and Intel (what GitHub Actions does).
- Layout and design notes: see `CLAUDE.md`.
