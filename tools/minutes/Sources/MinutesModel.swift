import AppKit
import Combine
import UserNotifications

enum AppActivity: Equatable {
    case idle, starting(UUID), recording(UUID), stopping(UUID), processing(UUID)
    var meetingID: UUID? {
        switch self {
        case .idle: nil
        case let .starting(id), let .recording(id), let .stopping(id), let .processing(id): id
        }
    }
    var recordingID: UUID? { if case let .recording(id) = self { id } else { nil } }
    var processingID: UUID? { if case let .processing(id) = self { id } else { nil } }
    var canToggle: Bool { self == .idle || recordingID != nil }
    var showsProgress: Bool { self != .idle && recordingID == nil }
}

@MainActor
final class MinutesModel: ObservableObject {
    @Published var meetings: [Meeting] = []
    @Published var selected: UUID?
    @Published private(set) var activity = AppActivity.idle
    @Published var status = "Ready · ⌥⇧M to record"
    @Published var error: String?
    @Published var settings = ProcessorSettings()
    @Published var elapsed = "0:00"
    let store: MeetingStore
    let support: URL
    let review: Bool
    private var recorder: Recorder?
    private var process: Process?
    private var sleepPrevention: NSObjectProtocol?
    var changed: (() -> Void)?
    var openWindow: (() -> Void)?
    var isWorking: Bool { activity != .idle }
    var selectedMeeting: Meeting? { meetings.first { $0.id == selected } }
    init(root: URL, support: URL, review: Bool) throws {
        self.store = try MeetingStore(root: root); self.support = support; self.review = review
        meetings = try store.load()
        selected = meetings.first?.id
        let settingsFile = support.appendingPathComponent("settings.json")
        if FileManager.default.fileExists(atPath: settingsFile.path) {
            do { settings = try JSONDecoder().decode(ProcessorSettings.self, from: Data(contentsOf: settingsFile)) }
            catch { settings.provider = "" }
        }
        if !settings.hasProvider { error = "Choose OpenAI or Anthropic in Provider. Your transcript will be sent to that provider through Pi; transcription stays on this Mac." }
    }
    func selectProvider(_ provider: String) {
        guard !isWorking, ProcessorSettings.choices.contains(where: { $0.id == provider }) else { return }
        do {
            var updated = settings; updated.provider = provider
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try JSONEncoder().encode(updated).write(to: support.appendingPathComponent("settings.json"), options: .atomic)
            settings = updated; error = nil; changed?()
        } catch { self.error = error.localizedDescription }
    }
    private func requireProvider() -> Bool {
        guard settings.hasProvider else {
            error = "Choose OpenAI or Anthropic in Provider before sending this transcript to Pi."; openWindow?(); return false
        }
        return true
    }
    func tick() {
        if let id = activity.recordingID, var meeting = meetings.first(where: { $0.id == id }) {
            meeting.duration = Date().timeIntervalSince(meeting.date)
            elapsed = Meeting.elapsed(meeting.duration)
            status = "Recording · \(elapsed)"
            if Int(meeting.duration) % 5 == 0 {
                do { try update(meeting) } catch { self.error = "Could not save recording progress: \(error.localizedDescription)" }
            }
        } else if let id = activity.processingID {
            status = (try? String(contentsOf: store.folder(id).appendingPathComponent("progress.txt"), encoding: .utf8)) ?? "Processing…"
        } else {
            switch activity {
            case .starting: status = "Starting recording…"
            case .stopping: status = "Saving recording…"
            default: status = "Ready · ⌥⇧M to record"
            }
        }
        changed?()
    }
    func toggle() {
        guard activity.canToggle else { openWindow?(); return }
        if activity.recordingID != nil { Task { await stop() }; return }
        guard requireProvider() else { return }
        guard FileManager.default.isExecutableFile(atPath: support.appendingPathComponent("runtime/bin/python3").path),
              FileManager.default.fileExists(atPath: support.appendingPathComponent("moonshine.json").path) else {
            error = "Moonshine is not installed. Run setup.sh from tools/minutes, then try again."; openWindow?(); return
        }
        let id = UUID()
        activity = .starting(id); tick()
        Task { await start(id) }
    }
    private func start(_ id: UUID) async {
        guard activity == .starting(id) else { return }
        var meeting = Meeting(id: id)
        do {
            try store.save(meeting)
            meetings.insert(meeting, at: 0); selected = meeting.id
            let capture = Recorder()
            capture.onFailure = { [weak self] message in
                Task { @MainActor in
                    guard let self, self.activity.recordingID != nil else { return }
                    await self.stop(captureFailure: message)
                }
            }
            recorder = capture
            try await capture.start(directory: store.folder(meeting.id).appendingPathComponent("audio"))
            meeting.date = Date(); try update(meeting)
            activity = .recording(meeting.id)
            sleepPrevention = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason: "Recording a meeting")
            if !review { Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) } }
        } catch {
            if let recorder { _ = try? await recorder.stop() }
            meeting.state = "failed"; meeting.error = error.localizedDescription
            do {
                let audio = store.folder(meeting.id).appendingPathComponent("audio")
                let exists = FileManager.default.fileExists(atPath: audio.path)
                let files = try? FileManager.default.contentsOfDirectory(at: audio, includingPropertiesForKeys: nil)
                if !exists || files?.isEmpty == true {
                    try store.delete(meeting.id)
                    meetings.removeAll { $0.id == meeting.id }; selected = meetings.first?.id
                } else { try update(meeting) }
            } catch { self.error = error.localizedDescription }
            recorder = nil; activity = .idle; self.error = meeting.error; openWindow?()
        }
        tick()
    }
    func stop(captureFailure: String? = nil) async {
        guard let id = activity.recordingID, var meeting = meetings.first(where: { $0.id == id }) else { return }
        activity = .stopping(id); tick()
        do {
            meeting.warning = try await recorder?.stop()
            if let captureFailure { throw MinutesError(captureFailure) }
        } catch { meeting.error = error.localizedDescription; meeting.state = "failed" }
        meeting.duration = Date().timeIntervalSince(meeting.date)
        recorder = nil; activity = .idle
        if let sleepPrevention { ProcessInfo.processInfo.endActivity(sleepPrevention); self.sleepPrevention = nil }
        do {
            if meeting.state != "failed" { meeting.state = "pending" }
            try update(meeting)
            if meeting.state == "failed" { notify(meeting, failed: true); openWindow?() }
            else { run(id) }
        } catch { self.error = "Could not save recording metadata: \(error.localizedDescription)"; openWindow?() }
        tick()
    }
    func run(_ id: UUID) {
        guard !isWorking, var meeting = meetings.first(where: { $0.id == id }) else { return }
        guard requireProvider() else { return }
        let folder = store.folder(id)
        activity = .processing(id)
        do {
            meeting.state = "processing"; meeting.error = nil
            meeting.processor = settings.label
            let settingsFile = folder.appendingPathComponent("processor.json")
            try JSONEncoder().encode(settings).write(to: settingsFile, options: .atomic)
            for name in ["result.json", "error.txt", "progress.txt"] {
                let url = folder.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            }
            try update(meeting)
            let process = Process()
            process.executableURL = support.appendingPathComponent("runtime/bin/python3")
            process.arguments = [Bundle.main.resourceURL!.appendingPathComponent("worker.py").path, folder.path, settingsFile.path, support.appendingPathComponent("moonshine.json").path]
            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = ["/opt/homebrew/bin", "/usr/local/bin", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin").path, environment["PATH"] ?? "/usr/bin:/bin"].joined(separator: ":")
            environment["PYTHONUNBUFFERED"] = "1"
            environment["PYTHONDONTWRITEBYTECODE"] = "1"
            process.environment = environment
            let log = folder.appendingPathComponent("processing.log")
            FileManager.default.createFile(atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600])
            let handle = try FileHandle(forWritingTo: log)
            process.standardOutput = handle; process.standardError = handle
            process.terminationHandler = { [weak self] process in
                try? handle.close()
                Task { @MainActor in self?.finished(id, exitCode: process.terminationStatus) }
            }
            try process.run()
            self.process = process
            sleepPrevention = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason: "Finishing a meeting note")
        } catch {
            activity = .idle
            meeting.state = "failed"; meeting.error = "Processing could not start: \(error.localizedDescription). Run setup.sh if Moonshine is missing."
            do { try update(meeting) } catch { self.error = error.localizedDescription }
        }
        tick()
    }
    private func finished(_ id: UUID, exitCode: Int32) {
        guard activity == .processing(id) else { return }
        activity = .idle; process = nil
        if let sleepPrevention { ProcessInfo.processInfo.endActivity(sleepPrevention); self.sleepPrevention = nil }
        guard var meeting = meetings.first(where: { $0.id == id }) else { return }
        do {
            guard exitCode == 0 else {
                let detail = (try? String(contentsOf: store.folder(id).appendingPathComponent("error.txt"), encoding: .utf8)) ?? "Worker exited with status \(exitCode). Open saved files for the processing log."
                throw MinutesError(detail)
            }
            let result = try JSONDecoder().decode(NoteResult.self, from: Data(contentsOf: store.folder(id).appendingPathComponent("result.json")))
            guard !result.title.isEmpty, !result.body.isEmpty else { throw MinutesError("The processor returned an empty note.") }
            meeting.title = result.title; meeting.body = result.body; meeting.state = "ready"; meeting.error = nil
            try update(meeting)
        } catch {
            meeting.state = "failed"; meeting.error = error.localizedDescription
            do { try update(meeting) } catch { self.error = "Could not save note: \(error.localizedDescription)" }
        }
        notify(meeting, failed: meeting.state == "failed"); tick()
    }
    func edit(_ id: UUID, title: String? = nil, body: String? = nil) {
        guard var meeting = meetings.first(where: { $0.id == id }) else { return }
        if let title { meeting.title = title }
        if let body { meeting.body = body }
        // Keep the user's correction in the editor even if storage becomes unavailable.
        if let index = meetings.firstIndex(where: { $0.id == id }) { meetings[index] = meeting }
        do { try store.save(meeting) } catch { self.error = "Edits could not be saved: \(error.localizedDescription)" }
    }
    private func update(_ meeting: Meeting) throws {
        try store.save(meeting)
        if let index = meetings.firstIndex(where: { $0.id == meeting.id }) { meetings[index] = meeting }
        else { meetings.insert(meeting, at: 0) }
    }
    func delete(_ id: UUID) {
        guard id != activity.meetingID else { return }
        do { try store.delete(id); meetings.removeAll { $0.id == id }; selected = meetings.first?.id }
        catch { self.error = "Could not delete meeting: \(error.localizedDescription)" }
    }
    func transcript(_ id: UUID) -> String? { try? String(contentsOf: store.folder(id).appendingPathComponent("transcript.txt"), encoding: .utf8) }
    func reveal(_ id: UUID) { NSWorkspace.shared.open(store.folder(id)) }
    private func notify(_ meeting: Meeting, failed: Bool) {
        guard !review else { return }
        let content = UNMutableNotificationContent()
        content.title = failed ? "Minutes needs attention" : "Your meeting note is ready"
        content.body = failed ? "Saved audio is available. Open Minutes to retry." : meeting.title
        content.userInfo = ["meeting": meeting.id.uuidString]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: meeting.id.uuidString, content: content, trigger: nil))
    }
}
