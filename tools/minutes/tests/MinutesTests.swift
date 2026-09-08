import Foundation
import AVFoundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw MinutesError(message) }
}
func sample(rate: Double, time: Double, seconds: Double = 0.02) throws -> CMSampleBuffer {
    let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
    let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(rate * seconds))!
    pcm.frameLength = pcm.frameCapacity
    for i in 0..<Int(pcm.frameLength) { pcm.floatChannelData![0][i] = Float(sin(Double(i) * 0.1) * 0.2) }
    var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: CMTimeScale(rate)), presentationTimeStamp: CMTime(seconds: time, preferredTimescale: 1000000), decodeTimeStamp: .invalid)
    var result: CMSampleBuffer?
    let status = CMSampleBufferCreate(allocator: kCFAllocatorDefault, dataBuffer: nil, dataReady: false, makeDataReadyCallback: nil, refcon: nil, formatDescription: format.formatDescription, sampleCount: CMItemCount(pcm.frameLength), sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &result)
    try expect(status == noErr, "Create sample")
    try expect(CMSampleBufferSetDataBufferFromAudioBufferList(result!, blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: 0, bufferList: pcm.audioBufferList) == noErr, "Attach audio")
    CMSampleBufferSetDataReady(result!)
    return result!
}
@main struct Tests {
    @MainActor static func main() throws {
        for (old, expected) in [("codex", "openai"), ("claude", "anthropic"), ("local", ""), ("unknown", "")] {
            let data = Data("{\"provider\":\"\(old)\",\"model\":\"old-model\",\"configured\":true}".utf8)
            let migrated = try JSONDecoder().decode(ProcessorSettings.self, from: data)
            try expect(migrated.provider == expected && migrated.hasProvider == !expected.isEmpty, "Provider migration must preserve remote consent")
        }
        let activeID = UUID()
        for state in [AppActivity.starting(activeID), .recording(activeID), .stopping(activeID), .processing(activeID)] {
            try expect(state.meetingID == activeID, "Every active phase protects its meeting from deletion")
            try expect(state.canToggle == (state == .recording(activeID)), "Only recording can be stopped; transitions cannot restart")
            try expect(state.showsProgress == (state != .recording(activeID)), "Progress reflects starting, stopping and processing")
        }
        try expect(AppActivity.idle.canToggle && AppActivity.idle.meetingID == nil, "Idle permits a new recording")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("minutes-tests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let profile = root.appendingPathComponent("profile")
        let appModel = try MinutesModel(root: profile.appendingPathComponent("meetings"), support: profile, review: true)
        try expect(appModel.settings.provider == "openai", "New installations default to OpenAI")
        appModel.selectProvider("anthropic")
        let reopened = try MinutesModel(root: profile.appendingPathComponent("meetings"), support: profile, review: true)
        try expect(reopened.settings.provider == "anthropic", "Provider selection saves immediately")
        try Data("{\"provider\":\"local\",\"configured\":true}".utf8).write(to: profile.appendingPathComponent("settings.json"))
        let local = try MinutesModel(root: profile.appendingPathComponent("meetings"), support: profile, review: true)
        local.toggle()
        try expect(!local.isWorking && !local.settings.hasProvider && local.error != nil, "Migrated Local must choose a remote provider")
        try Data("corrupt".utf8).write(to: profile.appendingPathComponent("settings.json"))
        let corrupt = try MinutesModel(root: profile.appendingPathComponent("meetings"), support: profile, review: true)
        try expect(!corrupt.settings.hasProvider, "Unreadable settings must not assume remote consent")
        let store = try MeetingStore(root: root)
        var meeting = Meeting(title: "Release review", body: "Release is approved.\n\nAction items\n☐ Ana sends the draft Friday.", state: "ready")
        try store.save(meeting)
        var loaded = try store.load()
        try expect(loaded.first == meeting, "Notes must survive restart")
        meeting.body += "\n☐ Verify the release."
        try store.save(meeting)
        loaded = try store.load()
        try expect(loaded.first?.body == meeting.body, "Corrections must persist")
        meeting.state = "processing"; try store.save(meeting)
        try "source".write(to: store.folder(meeting.id).appendingPathComponent("transcript.txt"), atomically: true, encoding: .utf8)
        loaded = try store.load()
        try expect(loaded.first?.state == "failed", "Interrupted work must offer retry")
        try expect(FileManager.default.fileExists(atPath: store.folder(meeting.id).appendingPathComponent("transcript.txt").path), "Recovery preserves transcript")
        try Data("broken".utf8).write(to: store.folder(meeting.id).appendingPathComponent("meeting.json"))
        loaded = try store.load()
        try expect(loaded.first?.id == meeting.id && loaded.first?.state == "failed", "Corrupt metadata must remain visible")
        try expect(FileManager.default.fileExists(atPath: store.folder(meeting.id).appendingPathComponent("meeting.recovered-original.json").path), "Corrupt metadata must be preserved before retry")
        try store.delete(meeting.id)
        try expect(!FileManager.default.fileExists(atPath: store.folder(meeting.id).path), "Deletion removes source files")
        try expect(Meeting.elapsed(3661) == "1:01:01", "Long duration formatting")
        let audio = root.appendingPathComponent("audio")
        try FileManager.default.createDirectory(at: audio, withIntermediateDirectories: true)
        let track = AudioTrack(name: "Microphone", directory: audio)
        try track.append(sample(rate: 44100, time: 101), origin: 100)
        try track.append(sample(rate: 44100, time: 101.02), origin: 100)
        try track.append(sample(rate: 48000, time: 162), origin: 100)
        track.close()
        let files = try FileManager.default.contentsOfDirectory(at: audio, includingPropertiesForKeys: nil).sorted { $0.path < $1.path }
        try expect(files.count == 2, "Gaps and device changes rotate files")
        let first = try AVAudioFile(forReading: files[0])
        let second = try AVAudioFile(forReading: files[1])
        try expect(first.length == 1764 && second.length == 960, "Both sample rates must write all frames")
        try expect(files[0].lastPathComponent.contains("00000001.000"), "Keep source timestamps")
        try expect(track.audible, "Capture detects audible input")
        let longTrack = AudioTrack(name: "System", directory: audio)
        for second in 0..<122 { try longTrack.append(sample(rate: 48000, time: 100 + Double(second), seconds: 1), origin: 100) }
        longTrack.close()
        let segments = try FileManager.default.contentsOfDirectory(at: audio, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("System") }
        try expect(segments.count == 3, "Continuous audio rotates every minute")
        var total: Int64 = 0
        for segment in segments {
            let file = try AVAudioFile(forReading: segment)
            try expect(file.length <= 60 * 48000, "Audio segments have bounded length")
            total += file.length
        }
        try expect(total == 122 * 48000, "Rotation preserves every audio frame")
        print("Passed persistence, recovery, deletion, durations, PCM capture, timestamps, gaps and device changes.")
    }
}
