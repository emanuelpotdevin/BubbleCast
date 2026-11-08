import AVFoundation
import AppKit

/// Layer-hosting view that shows the live camera, round in bubble mode and edge-to-edge in camera-only mode.
final class CameraView: NSView {
    let previewLayer: AVCaptureVideoPreviewLayer
    var isRound = true { didSet { needsLayout = true } }
    var onDoubleClick: (() -> Void)?
    var contextMenu: NSMenu?

    private let clipLayer = CALayer()
    private let clipMask = CAShapeLayer()
    private let ringLayer = CAShapeLayer()

    init(session: AVCaptureSession) {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)
        let root = CALayer()
        previewLayer.videoGravity = .resizeAspectFill
        // The video layer ignores plain corner rounding, so clip it with an explicit shape mask.
        clipLayer.masksToBounds = true
        clipLayer.backgroundColor = NSColor.black.cgColor
        clipLayer.mask = clipMask
        clipLayer.addSublayer(previewLayer)
        ringLayer.fillColor = nil
        ringLayer.strokeColor = NSColor.white.withAlphaComponent(0.85).cgColor
        ringLayer.lineWidth = 2.5
        root.addSublayer(clipLayer)
        root.addSublayer(ringLayer)
        layer = root
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    func applyMirroring() {
        guard let connection = previewLayer.connection, connection.isVideoMirroringSupported else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = true
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        clipLayer.frame = bounds
        previewLayer.frame = bounds
        let path = isRound ? CGPath(ellipseIn: bounds, transform: nil) : CGPath(rect: bounds, transform: nil)
        clipMask.frame = bounds
        clipMask.path = path
        clipLayer.cornerRadius = isRound ? min(bounds.width, bounds.height) / 2 : 0
        ringLayer.frame = bounds
        ringLayer.path = CGPath(ellipseIn: bounds.insetBy(dx: 1.25, dy: 1.25), transform: nil)
        ringLayer.isHidden = !isRound
        CATransaction.commit()
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick?()
        } else if isRound {
            window?.performDrag(with: event)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? { contextMenu }
}

/// Floating, borderless window holding the camera. It is a normal on-screen window, so the
/// screen recording picks it up wherever it is — which is what makes live mode switching work.
final class BubbleWindow: NSPanel {
    static let sizes: [CGFloat] = [160, 240, 340]
    let cameraView: CameraView
    private(set) var isFullscreen = false
    private var sizeIndex = 1
    private var savedFrame: NSRect?

    init(session: AVCaptureSession) {
        cameraView = CameraView(session: session)
        super.init(contentRect: NSRect(x: 0, y: 0, width: 240, height: 240),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .statusBar
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        contentView = cameraView
        cameraView.onDoubleClick = { [weak self] in self?.cycleSize() }
        cameraView.contextMenu = makeMenu()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func placeDefault(on screen: NSScreen) {
        let size = Self.sizes[sizeIndex]
        let v = screen.visibleFrame
        setFrame(NSRect(x: v.minX + 40, y: v.minY + 40, width: size, height: size), display: true)
    }

    func showBubble(on screen: NSScreen) {
        if isFullscreen {
            isFullscreen = false
            level = .statusBar
            hasShadow = true
            cameraView.isRound = true
            setFrame(savedFrame ?? frame, display: true, animate: isVisible)
        } else if savedFrame == nil {
            placeDefault(on: screen)
            savedFrame = frame
        }
        orderFrontRegardless()
    }

    func showFullscreen(on screen: NSScreen) {
        if !isFullscreen {
            if isVisible { savedFrame = frame }
            isFullscreen = true
            hasShadow = false
            // Above the menu bar and Dock so the recording shows only the camera.
            level = .screenSaver
            cameraView.isRound = false
        }
        if savedFrame == nil { placeDefault(on: screen); savedFrame = frame }
        let wasVisible = isVisible
        orderFrontRegardless()
        setFrame(screen.frame, display: true, animate: wasVisible)
    }

    func hide() { orderOut(nil) }

    func setSize(_ index: Int) {
        sizeIndex = index
        guard !isFullscreen else { return }
        let size = Self.sizes[index]
        let c = NSPoint(x: frame.midX, y: frame.midY)
        setFrame(NSRect(x: c.x - size / 2, y: c.y - size / 2, width: size, height: size), display: true, animate: true)
        savedFrame = frame
    }

    private func cycleSize() { setSize((sizeIndex + 1) % Self.sizes.count) }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        for (i, name) in ["Small", "Medium", "Large"].enumerated() {
            let item = NSMenuItem(title: name, action: #selector(sizeItem(_:)), keyEquivalent: "")
            item.tag = i
            item.target = self
            menu.addItem(item)
        }
        return menu
    }

    @objc private func sizeItem(_ sender: NSMenuItem) { setSize(sender.tag) }
}
