import AVFoundation
import AppKit
import ScreenCaptureKit

/// Records one display to a .mov with ScreenCaptureKit, including the mic and (optionally) system audio.
///
/// ScreenCaptureKit has no pause, so each stretch between pauses is written to its own temporary
/// segment file; stopping joins the segments into the final movie (passthrough, no re-encoding).
/// All state is touched on the main thread.
final class Recorder: NSObject, SCStreamDelegate, SCStreamOutput, SCRecordingOutputDelegate {
    private var stream: SCStream?
    private var config: SCStreamConfiguration?
    // Must be retained: ScreenCaptureKit does not keep the recording output alive on its own,
    // and if it is released the file is never written and no "finished" callback arrives.
    // Nil while paused.
    private var recordingOutput: SCRecordingOutput?
    private var segments: [URL] = []
    private var finalURL: URL?
    private var failure: Error?
    private var segmentDone: CheckedContinuation<Void, Never>?
    private let sampleQueue = DispatchQueue(label: "bubblecast.samples")
    var onFinish: ((URL?, Error?) -> Void)?

    static var outputFolder: URL {
        let url = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BubbleCast", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @MainActor
    func start(screen: NSScreen, excluding hiddenIDs: Set<CGWindowID>, micID: String?, systemAudio: Bool, showsCursor: Bool) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else {
            throw NSError(domain: "BubbleCast", code: 1, userInfo: [NSLocalizedDescriptionKey: "No display found."])
        }
        let excluded = content.windows.filter { hiddenIDs.contains($0.windowID) }
        let filter = SCContentFilter(display: display, excludingWindows: excluded)

        let config = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        config.width = Int(filter.contentRect.width * scale)
        config.height = Int(filter.contentRect.height * scale)
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.queueDepth = 6
        config.showsCursor = showsCursor
        config.capturesAudio = systemAudio
        config.excludesCurrentProcessAudio = true
        if let micID {
            config.captureMicrophone = true
            config.microphoneCaptureDeviceID = micID
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        finalURL = Self.outputFolder.appendingPathComponent("BubbleCast \(formatter.string(from: Date())).mov")
        segments = []
        failure = nil

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        // No-op sample outputs keep ScreenCaptureKit from dropping/complaining about unclaimed buffers.
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        if systemAudio { try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue) }
        if micID != nil { try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: sampleQueue) }
        self.stream = stream
        self.config = config
        do {
            try beginSegment()
            try await stream.startCapture()
        } catch {
            reset()
            throw error
        }
    }

    @MainActor
    func pause() async { await endSegment() }

    @MainActor
    func resume() throws { try beginSegment() }

    @MainActor
    func stop() async {
        guard let stream, let finalURL else { return }
        await endSegment()
        try? await stream.stopCapture()
        let parts = segments
        let error = failure
        reset()
        do {
            try await Self.join(parts, into: finalURL)
            for part in parts { try? FileManager.default.removeItem(at: part) }
            onFinish?(finalURL, error)
        } catch {
            onFinish?(nil, error) // segments are left in the temp folder so nothing is lost
        }
    }

    /// Hide the cursor while in camera-only mode, show it again for screen modes.
    func setShowsCursor(_ shows: Bool) {
        guard let stream, let config, config.showsCursor != shows else { return }
        config.showsCursor = shows
        stream.updateConfiguration(config) { _ in }
    }

    // MARK: Segments

    @MainActor
    private func beginSegment() throws {
        guard let stream, recordingOutput == nil else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("BubbleCast-segment-\(UUID().uuidString).mov")
        let recordingConfig = SCRecordingOutputConfiguration()
        recordingConfig.outputURL = url
        recordingConfig.outputFileType = .mov
        recordingConfig.videoCodecType = .hevc
        let output = SCRecordingOutput(configuration: recordingConfig, delegate: self)
        try stream.addRecordingOutput(output)
        recordingOutput = output
        segments.append(url)
    }

    /// Closes the current segment file and waits until it is fully written.
    @MainActor
    private func endSegment() async {
        guard let stream, let output = recordingOutput else { return }
        recordingOutput = nil
        await withCheckedContinuation { continuation in
            segmentDone = continuation
            do { try stream.removeRecordingOutput(output) } catch { segmentFinished() }
            // Safety net: never hang if the "finished" callback doesn't come.
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { MainActor.assumeIsolated { self.segmentFinished() } }
        }
    }

    @MainActor
    private func segmentFinished() {
        segmentDone?.resume()
        segmentDone = nil
    }

    private func reset() {
        stream = nil
        config = nil
        recordingOutput = nil
        finalURL = nil
    }

    /// Joins the segment files into one movie without re-encoding.
    private static func join(_ parts: [URL], into output: URL) async throws {
        let usable = parts.filter { ((try? FileManager.default.attributesOfItem(atPath: $0.path)[.size] as? Int) ?? 0) > 0 }
        guard !usable.isEmpty else {
            throw NSError(domain: "BubbleCast", code: 2, userInfo: [NSLocalizedDescriptionKey: "Nothing was recorded."])
        }
        if usable.count == 1 {
            try FileManager.default.moveItem(at: usable[0], to: output)
            return
        }
        let composition = AVMutableComposition()
        var cursor = CMTime.zero
        for url in usable {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration)
            guard duration > .zero else { continue }
            try await composition.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: asset, at: cursor)
            cursor = cursor + duration
        }
        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw NSError(domain: "BubbleCast", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not join the recording."])
        }
        try await export.export(to: output, as: .mov)
    }

    // MARK: SCStreamOutput / delegates

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {}

    /// The stream ended on its own (e.g. "Stop Sharing" from the menu bar): save what we have.
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async {
            self.failure = error
            Task { await self.stop() }
        }
    }

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        DispatchQueue.main.async { MainActor.assumeIsolated { self.segmentFinished() } }
    }

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.failure = error
            MainActor.assumeIsolated { self.segmentFinished() }
        }
    }
}
