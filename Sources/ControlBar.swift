import AppKit

enum Mode: Int { case screenAndCam, screenOnly, camOnly }
enum RecordingPhase { case idle, recording, paused }

protocol ControlBarDelegate: AnyObject {
    func toggleRecording()
    func togglePause()
    func setMode(_ mode: Mode)
    func toggleBubble()
    func toggleMic()
    func toggleSystemAudio()
    func settingsMenu() -> NSMenu
}

/// The floating toolbar. It is excluded from the recording, so it never shows up in the video.
final class ControlBar: NSPanel {
    weak var controller: ControlBarDelegate?
    private let recordButton = NSButton()
    private let pauseButton = NSButton()
    private let modeControl = NSSegmentedControl()
    private let bubbleButton = NSButton()
    private let micButton = NSButton()
    private let audioButton = NSButton()
    private let settingsButton = NSButton()

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 600, height: 52),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 16
        background.layer?.masksToBounds = true

        recordButton.bezelStyle = .rounded
        recordButton.bezelColor = .systemRed
        recordButton.controlSize = .large
        recordButton.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        recordButton.target = self
        recordButton.action = #selector(recordClicked)
        recordButton.toolTip = "Start / stop recording  (⌥⌘R)"

        pauseButton.bezelStyle = .rounded
        pauseButton.bezelColor = .systemOrange
        pauseButton.controlSize = .large
        pauseButton.imagePosition = .imageLeading
        pauseButton.target = self
        pauseButton.action = #selector(pauseClicked)
        pauseButton.toolTip = "Pause / resume recording  (⌥⌘P)"
        pauseButton.isHidden = true

        modeControl.segmentCount = 3
        modeControl.trackingMode = .selectOne
        modeControl.controlSize = .large
        let modes: [(String, String, String)] = [
            ("Screen + Cam", "pip", "⌥⌘1"), ("Screen", "display", "⌥⌘2"), ("Camera", "video", "⌥⌘3"),
        ]
        for (i, (label, symbol, key)) in modes.enumerated() {
            modeControl.setLabel(label, forSegment: i)
            modeControl.setImage(NSImage(systemSymbolName: symbol, accessibilityDescription: label), forSegment: i)
            modeControl.setImageScaling(.scaleProportionallyDown, forSegment: i)
            modeControl.setToolTip("\(label)  (\(key))", forSegment: i)
        }
        modeControl.target = self
        modeControl.action = #selector(modeChanged)

        for (button, action, tip) in [
            (bubbleButton, #selector(bubbleClicked), "Webcam bubble on / off  (⌥⌘B)"),
            (micButton, #selector(micClicked), "Microphone on / off"),
            (audioButton, #selector(audioClicked), "Record system audio on / off"),
            (settingsButton, #selector(settingsClicked), "Camera, microphone, folder…"),
        ] {
            button.isBordered = false
            button.imageScaling = .scaleProportionallyUpOrDown
            button.symbolConfiguration = .init(pointSize: 17, weight: .medium)
            button.target = self
            button.action = action
            button.toolTip = tip
            button.widthAnchor.constraint(equalToConstant: 30).isActive = true
        }
        settingsButton.image = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: "Settings")
        settingsButton.contentTintColor = .secondaryLabelColor

        let grip = NSImageView(image: NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: nil)!)
        grip.contentTintColor = .tertiaryLabelColor
        grip.toolTip = "Drag to move"

        let stack = NSStackView(views: [grip, recordButton, pauseButton, divider(), modeControl, divider(),
                                        bubbleButton, micButton, audioButton, settingsButton])
        stack.orientation = .horizontal
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 14, bottom: 8, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            stack.topAnchor.constraint(equalTo: background.topAnchor),
            stack.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            recordButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 110),
        ])
        contentView = background
        setContentSize(stack.fittingSize)
    }

    override var canBecomeKey: Bool { false }

    private func divider() -> NSView {
        let box = NSBox()
        box.boxType = .separator
        box.heightAnchor.constraint(equalToConstant: 24).isActive = true
        return box
    }

    func placeDefault(on screen: NSScreen) {
        let v = screen.visibleFrame
        setFrameOrigin(NSPoint(x: v.midX - frame.width / 2, y: v.minY + 24))
    }

    // MARK: State

    func update(mode: Mode, mic: Bool, systemAudio: Bool, recordTitle: String, phase: RecordingPhase) {
        let isRecording = phase != .idle
        modeControl.selectedSegment = mode.rawValue
        let bubbleOn = mode == .screenAndCam
        bubbleButton.image = NSImage(systemSymbolName: bubbleOn ? "person.crop.circle.fill" : "person.crop.circle.badge.xmark",
                                     accessibilityDescription: "Bubble")
        bubbleButton.contentTintColor = bubbleOn ? .systemGreen : .secondaryLabelColor
        micButton.image = NSImage(systemSymbolName: mic ? "mic.fill" : "mic.slash", accessibilityDescription: "Mic")
        micButton.contentTintColor = mic ? .systemGreen : .secondaryLabelColor
        audioButton.image = NSImage(systemSymbolName: systemAudio ? "speaker.wave.2.fill" : "speaker.slash",
                                    accessibilityDescription: "System audio")
        audioButton.contentTintColor = systemAudio ? .systemGreen : .secondaryLabelColor
        // Audio sources are fixed once a recording starts.
        micButton.isEnabled = !isRecording
        audioButton.isEnabled = !isRecording
        recordButton.title = recordTitle
        recordButton.image = NSImage(systemSymbolName: isRecording ? "stop.fill" : "record.circle",
                                     accessibilityDescription: nil)
        recordButton.imagePosition = .imageLeading
        recordButton.toolTip = isRecording ? "Stop and save  (⌥⌘R)" : "Start recording  (⌥⌘R)"

        let wasHidden = pauseButton.isHidden
        pauseButton.isHidden = !isRecording
        pauseButton.title = phase == .paused ? "Resume" : "Pause"
        pauseButton.image = NSImage(systemSymbolName: phase == .paused ? "play.fill" : "pause.fill",
                                    accessibilityDescription: nil)
        if wasHidden != pauseButton.isHidden { resizeToFit() }
    }

    /// Grow/shrink around the centre when the Pause button appears or disappears.
    private func resizeToFit() {
        guard let content = contentView else { return }
        content.layoutSubtreeIfNeeded()
        let size = content.fittingSize
        let midX = frame.midX
        setFrame(NSRect(x: midX - size.width / 2, y: frame.minY, width: size.width, height: size.height), display: true)
    }

    // MARK: Actions

    @objc private func recordClicked() { controller?.toggleRecording() }
    @objc private func pauseClicked() { controller?.togglePause() }
    @objc private func modeChanged() { controller?.setMode(Mode(rawValue: modeControl.selectedSegment) ?? .screenAndCam) }
    @objc private func bubbleClicked() { controller?.toggleBubble() }
    @objc private func micClicked() { controller?.toggleMic() }
    @objc private func audioClicked() { controller?.toggleSystemAudio() }
    @objc private func settingsClicked() {
        guard let menu = controller?.settingsMenu() else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: settingsButton.bounds.height + 4), in: settingsButton)
    }
}
