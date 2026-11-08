import AVFoundation
import AppKit
import Carbon
import ScreenCaptureKit

final class AppController: NSObject, NSApplicationDelegate, ControlBarDelegate {
    enum State { case idle, countdown(Int), starting, recording, pausing, paused, stopping }

    private let camera = Camera()
    private lazy var bubble = BubbleWindow(session: camera.session)
    private let bar = ControlBar()
    private let recorder = Recorder()
    private var mode = Mode.screenAndCam
    private var micOn = true
    private var systemAudioOn = false
    private var micID = AVCaptureDevice.default(for: .audio)?.uniqueID
    private var state = State.idle
    private var timer: Timer?
    private var recordingScreen: NSScreen?
    private var quitAfterSaving = false
    // Recorded time excluding pauses: finished stretches plus the one in progress.
    private var elapsedBeforePause: TimeInterval = 0
    private var stretchStart: Date?

    private var elapsed: TimeInterval {
        elapsedBeforePause + (stretchStart.map { Date().timeIntervalSince($0) } ?? 0)
    }

    private var isRecording: Bool {
        switch state {
        case .idle, .countdown: return false
        default: return true
        }
    }

    private var activeScreen: NSScreen {
        recordingScreen ?? bar.screen ?? NSScreen.main ?? NSScreen.screens[0]
    }

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMainMenu()
        camera.onConfigured = { [weak self] in self?.bubble.cameraView.applyMirroring() }
        recorder.onFinish = { [weak self] url, error in self?.recordingFinished(url: url, error: error) }

        bar.controller = self
        bar.placeDefault(on: NSScreen.main ?? NSScreen.screens[0])
        bar.orderFrontRegardless()
        applyMode()

        HotKeys.register(keyCode: kVK_ANSI_R) { [weak self] in self?.toggleRecording() }
        HotKeys.register(keyCode: kVK_ANSI_P) { [weak self] in self?.togglePause() }
        HotKeys.register(keyCode: kVK_ANSI_B) { [weak self] in self?.toggleBubble() }
        HotKeys.register(keyCode: kVK_ANSI_1) { [weak self] in self?.setMode(.screenAndCam) }
        HotKeys.register(keyCode: kVK_ANSI_2) { [weak self] in self?.setMode(.screenOnly) }
        HotKeys.register(keyCode: kVK_ANSI_3) { [weak self] in self?.setMode(.camOnly) }

        AVCaptureDevice.requestAccess(for: .audio) { _ in }
        if selfTest { runSelfTest() }
    }

    // `--selftest`: record 2s, pause 2s, record 2s more, report the saved file on stdout, and quit (for debugging).
    private let selfTest = CommandLine.arguments.contains("--selftest")

    private func runSelfTest() {
        micOn = false
        startRecording()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.togglePause() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { self.togglePause() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 7) { self.stopRecording() }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        switch state {
        case .recording, .paused: break
        default: return .terminateNow
        }
        quitAfterSaving = true
        stopRecording()
        return .terminateLater
    }

    // MARK: ControlBarDelegate

    func toggleRecording() {
        switch state {
        case .idle: startCountdown()
        case .countdown: timer?.invalidate(); state = .idle; refresh()
        case .recording, .paused: stopRecording()
        case .starting, .pausing, .stopping: break
        }
    }

    func togglePause() {
        switch state {
        case .recording:
            state = .pausing
            elapsedBeforePause = elapsed
            stretchStart = nil
            refresh()
            Task {
                await recorder.pause()
                await MainActor.run {
                    // Stop may have been pressed while the pause was finishing.
                    if case .pausing = self.state { self.state = .paused }
                    self.refresh()
                }
            }
        case .paused:
            do {
                try MainActor.assumeIsolated { try recorder.resume() } // UI actions run on main
                state = .recording
                stretchStart = Date()
            } catch {
                NSAlert(error: error).runModal()
            }
            refresh()
        default: break
        }
    }

    func setMode(_ newMode: Mode) {
        mode = newMode
        applyMode()
    }

    func toggleBubble() {
        setMode(mode == .screenAndCam ? .screenOnly : .screenAndCam)
    }

    func toggleMic() {
        guard !isRecording else { return }
        micOn.toggle()
        refresh()
    }

    func toggleSystemAudio() {
        guard !isRecording else { return }
        systemAudioOn.toggle()
        refresh()
    }

    func settingsMenu() -> NSMenu {
        let menu = NSMenu()

        let cameraMenu = NSMenu()
        let current = camera.device?.uniqueID ?? AVCaptureDevice.default(for: .video)?.uniqueID
        for device in Camera.availableDevices {
            let item = NSMenuItem(title: device.localizedName, action: #selector(pickCamera(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = device
            item.state = device.uniqueID == current ? .on : .off
            cameraMenu.addItem(item)
        }
        menu.addItem(withTitle: "Camera", action: nil, keyEquivalent: "").submenu = cameraMenu

        let micMenu = NSMenu()
        let mics = AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external],
                                                    mediaType: .audio, position: .unspecified).devices
        for device in mics {
            let item = NSMenuItem(title: device.localizedName, action: #selector(pickMic(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = device.uniqueID
            item.state = device.uniqueID == micID ? .on : .off
            item.isEnabled = !isRecording
            micMenu.addItem(item)
        }
        menu.addItem(withTitle: "Microphone", action: nil, keyEquivalent: "").submenu = micMenu

        let sizeMenu = NSMenu()
        for (i, name) in ["Small", "Medium", "Large"].enumerated() {
            let item = NSMenuItem(title: name, action: #selector(pickSize(_:)), keyEquivalent: "")
            item.target = self
            item.tag = i
            sizeMenu.addItem(item)
        }
        menu.addItem(withTitle: "Bubble Size", action: nil, keyEquivalent: "").submenu = sizeMenu

        menu.addItem(.separator())
        menu.addItem(withTitle: "Open Recordings Folder", action: #selector(openFolder), keyEquivalent: "").target = self

        menu.addItem(.separator())
        for line in ["⌥⌘R  Start / stop", "⌥⌘P  Pause / resume", "⌥⌘B  Bubble on / off",
                     "⌥⌘1  Screen + Cam", "⌥⌘2  Screen only", "⌥⌘3  Camera only"] {
            let item = NSMenuItem(title: line, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit BubbleCast", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    @objc private func pickCamera(_ sender: NSMenuItem) { camera.select(sender.representedObject as? AVCaptureDevice) }
    @objc private func pickMic(_ sender: NSMenuItem) { micID = sender.representedObject as? String; micOn = true; refresh() }
    @objc private func pickSize(_ sender: NSMenuItem) { bubble.setSize(sender.tag) }
    @objc private func openFolder() { NSWorkspace.shared.open(Recorder.outputFolder) }

    // MARK: Mode

    private func applyMode() {
        switch mode {
        case .screenAndCam:
            camera.start()
            bubble.showBubble(on: activeScreen)
        case .screenOnly:
            bubble.hide()
            camera.stop() // camera light goes off when the bubble is off
        case .camOnly:
            camera.start()
            bubble.showFullscreen(on: activeScreen)
        }
        recorder.setShowsCursor(mode != .camOnly)
        refresh()
    }

    // MARK: Recording

    private func startCountdown() {
        state = .countdown(3)
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
            guard let self, case .countdown(let n) = self.state else { t.invalidate(); return }
            if n <= 1 {
                t.invalidate()
                self.startRecording()
            } else {
                self.state = .countdown(n - 1)
                self.refresh()
            }
        }
    }

    private func startRecording() {
        state = .starting
        recordingScreen = bar.screen ?? NSScreen.main
        refresh()
        // Re-place the camera on the recorded display, in case the bar was moved to another screen.
        if mode != .screenOnly { applyMode() }
        let screen = activeScreen
        let mic = micOn ? micID : nil
        let audio = systemAudioOn
        let cursor = mode != .camOnly
        let hidden: Set<CGWindowID> = [CGWindowID(bar.windowNumber)]
        Task {
            do {
                try await recorder.start(screen: screen, excluding: hidden, micID: mic, systemAudio: audio, showsCursor: cursor)
                await MainActor.run {
                    self.state = .recording
                    self.elapsedBeforePause = 0
                    self.stretchStart = Date()
                    self.timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.refresh() }
                    self.refresh()
                }
            } catch {
                await MainActor.run {
                    self.state = .idle
                    self.recordingScreen = nil
                    self.refresh()
                    self.showStartError(error)
                }
            }
        }
    }

    private func stopRecording() {
        timer?.invalidate()
        stretchStart = nil
        state = .stopping
        refresh()
        Task { await recorder.stop() }
    }

    private func recordingFinished(url: URL?, error: Error?) {
        timer?.invalidate()
        state = .idle
        recordingScreen = nil
        refresh()
        if selfTest {
            let size = url.flatMap { try? FileManager.default.attributesOfItem(atPath: $0.path)[.size] as? Int } ?? 0
            print("SELFTEST url=\(url?.path ?? "nil") bytes=\(size) error=\(error.map { "\($0)" } ?? "none")")
            exit(size > 0 ? 0 : 1)
        }
        if let url, FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else if let error {
            let alert = NSAlert(error: error)
            alert.messageText = "The recording could not be saved."
            alert.runModal()
        }
        if quitAfterSaving { NSApp.reply(toApplicationShouldTerminate: true) }
    }

    private func showStartError(_ error: Error) {
        let nsError = error as NSError
        if nsError.domain == SCStreamErrorDomain, nsError.code == SCStreamError.userDeclined.rawValue {
            Permissions.showDenied("Screen & System Audio Recording", pane: "Privacy_ScreenCapture")
        } else {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert(error: error)
            alert.messageText = "Could not start recording"
            alert.informativeText = error.localizedDescription +
                "\n\nIf you just granted Screen Recording permission, quit and reopen BubbleCast."
            alert.runModal()
        }
    }

    private func refresh() {
        let title: String
        switch state {
        case .idle: title = "Record"
        case .countdown(let n): title = "\(n)…"
        case .starting: title = "Starting…"
        case .recording, .pausing, .paused:
            let s = Int(elapsed)
            title = String(format: "Stop  %02d:%02d", s / 60, s % 60)
        case .stopping: title = "Saving…"
        }
        let phase: RecordingPhase
        switch state {
        case .recording: phase = .recording
        case .pausing, .paused: phase = .paused
        default: phase = .idle
        }
        bar.update(mode: mode, mic: micOn, systemAudio: systemAudioOn, recordTitle: title, phase: phase)
    }

    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit BubbleCast", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        return main
    }
}

let app = NSApplication.shared
let controller = AppController()
app.delegate = controller
app.setActivationPolicy(.regular)
app.run()
