import AVFoundation
import AppKit

/// Owns the webcam capture session that feeds the bubble / full-screen camera view.
final class Camera {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "bubblecast.camera")
    private var input: AVCaptureDeviceInput?
    private(set) var device: AVCaptureDevice?
    var onConfigured: (() -> Void)?

    static var availableDevices: [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video, position: .unspecified
        ).devices
    }

    init() {
        session.sessionPreset = .high
    }

    func select(_ newDevice: AVCaptureDevice?) {
        queue.async { [self] in
            guard let newDevice = newDevice ?? AVCaptureDevice.default(for: .video),
                  let newInput = try? AVCaptureDeviceInput(device: newDevice) else { return }
            session.beginConfiguration()
            if let input { session.removeInput(input) }
            if session.canAddInput(newInput) {
                session.addInput(newInput)
                input = newInput
                device = newDevice
            }
            session.commitConfiguration()
            DispatchQueue.main.async { self.onConfigured?() }
        }
    }

    func start() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            guard granted else {
                DispatchQueue.main.async { Permissions.showDenied("Camera", pane: "Privacy_Camera") }
                return
            }
            // The queue is serial, so the device is configured before the session starts.
            if self.input == nil { self.select(nil) }
            self.queue.async { [self] in
                if !session.isRunning { session.startRunning() }
            }
        }
    }

    func stop() {
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }
}

enum Permissions {
    static func showDenied(_ what: String, pane: String) {
        let alert = NSAlert()
        alert.messageText = "\(what) access is needed"
        alert.informativeText = "Allow BubbleCast in System Settings → Privacy & Security → \(what), then try again."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}
