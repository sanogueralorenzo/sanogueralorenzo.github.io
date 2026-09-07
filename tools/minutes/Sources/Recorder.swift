import AppKit
import AVFoundation
import ScreenCaptureKit

struct MinutesError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

// Owned exclusively by Recorder's serial audio queue. Each completed CAF survives a crash.
final class AudioTrack {
    private var file: AVAudioFile?
    private var segmentStart = 0.0
    private var expectedTime = 0.0
    private var index = 0
    private var format: AVAudioFormat?
    let name: String
    let directory: URL
    private(set) var frames: Int64 = 0
    private(set) var audible = false
    init(name: String, directory: URL) { self.name = name; self.directory = directory }
    func append(_ sample: CMSampleBuffer, origin: Double) throws {
        guard CMSampleBufferDataIsReady(sample), let description = sample.formatDescription else { return }
        let format = AVAudioFormat(cmAudioFormatDescription: description)
        var retained: CMBlockBuffer?
        var size = 0
        CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sample, bufferListSizeNeededOut: &size, bufferListOut: nil, bufferListSize: 0, blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: 0, blockBufferOut: nil)
        let storage = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { storage.deallocate() }
        let list = storage.bindMemory(to: AudioBufferList.self, capacity: 1)
        let result = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sample, bufferListSizeNeededOut: nil, bufferListOut: list, bufferListSize: size, blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: 0, blockBufferOut: &retained)
        guard result == noErr, let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: list) else {
            throw MinutesError("Could not decode \(name.lowercased()) audio (\(result)).")
        }
        let time = max(0, sample.presentationTimeStamp.seconds - origin)
        // Preserve gaps/device changes as new timestamped segments rather than collapsing silence.
        if file == nil || time - segmentStart >= 60 || abs(time - expectedTime) > 0.15 || self.format != format {
            file = nil
            let url = directory.appendingPathComponent(String(format: "%@_%012.3f_%05d.caf", name, time, index))
            file = try AVAudioFile(forWriting: url, settings: format.settings, commonFormat: format.commonFormat, interleaved: format.isInterleaved)
            segmentStart = time; index += 1; self.format = format
        }
        try file!.write(from: buffer)
        frames += Int64(buffer.frameLength)
        expectedTime = time + Double(buffer.frameLength) / format.sampleRate
        if let channels = buffer.floatChannelData {
            for channel in 0..<Int(format.channelCount) {
                if (0..<Int(buffer.frameLength)).contains(where: { abs(channels[channel][$0]) > 0.002 }) { audible = true }
            }
        } else { audible = true }
    }
    func close() { file = nil }
}

final class Recorder: NSObject, SCStreamOutput, SCStreamDelegate {
    private let queue = DispatchQueue(label: "Minutes.audio", qos: .userInitiated)
    private var stream: SCStream?
    private var mic: AudioTrack!
    private var system: AudioTrack!
    private var origin = 0.0
    private var failure: Error?
    private var accepting = false
    var onFailure: ((String) -> Void)?
    func start(directory: URL) async throws {
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            throw MinutesError("Enable Minutes in System Settings → Privacy & Security → Microphone, then try again.")
        }
        let content: SCShareableContent
        do { content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) }
        catch { throw MinutesError("Enable Minutes in System Settings → Privacy & Security → Screen & System Audio Recording, then reopen Minutes. \(error.localizedDescription)") }
        guard let display = content.displays.first else { throw MinutesError("No display is available for system audio capture.") }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let config = SCStreamConfiguration()
        config.width = 2; config.height = 2; config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        config.capturesAudio = true; config.captureMicrophone = true
        config.excludesCurrentProcessAudio = true; config.sampleRate = 48000; config.channelCount = 1
        config.showsCursor = false
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: queue)
        self.stream = stream
        queue.sync {
            mic = AudioTrack(name: "Microphone", directory: directory)
            system = AudioTrack(name: "System", directory: directory)
            origin = CMClockGetTime(CMClockGetHostTimeClock()).seconds
            failure = nil; accepting = true
        }
        do {
            try await stream.startCapture()
            try queue.sync { if let failure { throw failure } }
        }
        catch { queue.sync { accepting = false; mic.close(); system.close() }; self.stream = nil; throw error }
    }
    func stop() async throws -> String? {
        var stopError: Error?
        if let stream { do { try await stream.stopCapture() } catch { stopError = error } }
        self.stream = nil
        return try queue.sync {
            accepting = false; mic?.close(); system?.close()
            if let failure { throw failure }
            if let stopError { throw stopError }
            guard let mic, let system else { throw MinutesError("Audio capture did not start.") }
            guard mic.frames > 0, system.frames > 0 else { throw MinutesError("One audio source delivered no samples. Check microphone and system audio permissions. Available audio is saved; Retry can process it.") }
            var warnings: [String] = []
            if !mic.audible { warnings.append("Microphone was silent.") }
            if !system.audible { warnings.append("System audio was silent.") }
            return warnings.isEmpty ? nil : warnings.joined(separator: " ") + " Check your input/output devices if speech is missing."
        }
    }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard accepting else { return }
        do {
            if type == .microphone { try mic.append(sampleBuffer, origin: origin) }
            if type == .audio { try system.append(sampleBuffer, origin: origin) }
        } catch {
            accepting = false; failure = error
            onFailure?("Audio capture stopped: \(error.localizedDescription)")
        }
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        queue.async { self.failure = error; self.accepting = false; self.onFailure?(error.localizedDescription) }
    }
}
