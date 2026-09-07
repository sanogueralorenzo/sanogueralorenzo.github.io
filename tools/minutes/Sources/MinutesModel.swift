import AppKit
import Combine
import UserNotifications

@MainActor
final class MinutesModel: ObservableObject {
    @Published var meetings: [Meeting] = []
    @Published var selected: UUID?
    @Published var recording: UUID?
    @Published var busy: UUID?
    @Published var transitioning = false
    @Published var status = "Ready · ⌥⇧M to record"
    @Published var error: String?
    @Published var settings = ProcessorSettings()
    @Published var settingsOpen = false
    @Published var elapsed = "0:00"
    let store: MeetingStore
    let support: URL
    let review: Bool
    private var recorder: Recorder?
    private var process: Process?
    private var activity: NSObjectProtocol?
    var changed: (() -> Void)?
    var openWindow: (() -> Void)?
    var isWorking: Bool { recording != nil || busy != nil || transitioning }
    var selectedMeeting: Meeting? { meetings.first { $0.id == selected } }
    init(root: URL, support: URL, review: Bool) throws {
        self.store = try MeetingStore(root: root); self.support = support; self.review = review
        meetings = try store.load()
        selected = meetings.first?.id
        if let data = try? Data(contentsOf: support.appendingPathComponent("settings.json")),
           let value = try? JSONDecoder().decode(ProcessorSettings.self, from: data) { settings = value }
        settingsOpen = !settings.configured && !review
    }
    func saveSettings() {
        do {
            guard ["local", "codex", "claude"].contains(settings.provider) else { throw MinutesError("Select a processor.") }
            if settings.provider == "local" && settings.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw MinutesError("Enter an installed Ollama model.") }
            settings.configured = true
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try JSONEncoder().encode(settings).write(to: support.appendingPathComponent("settings.json"), options: .atomic)
            settingsOpen = false
        } catch { self.error = error.localizedDescription }
    }
    func tick() {
        if let id = recording, var meeting = meetings.first(where: { $0.id == id }) {
            meeting.duration = Date().timeIntervalSince(meeting.date)
            elapsed = Meeting.elapsed(meeting.duration)
            status = "Recording · \(elapsed)"
            if Int(meeting.duration) % 5 == 0 {
                do { try update(meeting) } catch { self.error = "Could not save recording progress: \(error.localizedDescription)" }
            }
        } else if let id = busy {
            status = (try? String(contentsOf: store.folder(id).appendingPathComponent("progress.txt"), encoding: .utf8)) ?? "Processing…"
        } else { status = "Ready · ⌥⇧M to record" }
        changed?()
    }
    func toggle() {
        guard !transitioning else { return }
        if recording != nil { Task { await stop() }; return }
        guard busy == nil else { openWindow?(); return }
        guard settings.configured else { settingsOpen = true; openWindow?(); return }
        guard FileManager.default.isExecutableFile(atPath: support.appendingPathComponent("runtime/bin/python3").path),
              FileManager.default.fileExists(atPath: support.appendingPathComponent("moonshine.json").path) else {
            error = "Moonshine is not installed. Run setup.sh from tools/minutes, then try again."; openWindow?(); return
        }
        Task { await start() }
    }
    private func start() async {
        transitioning = true; changed?()
        var meeting = Meeting()
        do {
            try store.save(meeting)
            meetings.insert(meeting, at: 0); selected = meeting.id
            let capture = Recorder()
            capture.onFailure = { [weak self] message in
                Task { @MainActor in
                    guard let self, self.recording != nil, !self.transitioning else { return }
                    await self.stop(captureFailure: message)
                }
            }
            recorder = capture
            try await capture.start(directory: store.folder(meeting.id).appendingPathComponent("audio"))
            meeting.date = Date(); try update(meeting)
            recording = meeting.id
            activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason: "Recording a meeting")
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
            recorder = nil; self.error = meeting.error; openWindow?()
        }
        transitioning = false; tick()
    }
    func stop(captureFailure: String? = nil) async {
        guard let id = recording, var meeting = meetings.first(where: { $0.id == id }) else { return }
        transitioning = true
        do {
            meeting.warning = try await recorder?.stop()
            if let captureFailure { throw MinutesError(captureFailure) }
        } catch { meeting.error = error.localizedDescription; meeting.state = "failed" }
        meeting.duration = Date().timeIntervalSince(meeting.date)
        recorder = nil; recording = nil; transitioning = false
        if let activity { ProcessInfo.processInfo.endActivity(activity); self.activity = nil }
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
        guard settings.configured else { settingsOpen = true; return }
        let folder = store.folder(id)
        do {
            meeting.state = "processing"; meeting.error = nil
            meeting.processor = settings.provider == "local" ? "Local · \(settings.model)" : "\(settings.provider.capitalized) CLI"
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
            self.process = process; busy = id
            activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason: "Finishing a meeting note")
        } catch {
            meeting.state = "failed"; meeting.error = "Processing could not start: \(error.localizedDescription). Run setup.sh if Moonshine is missing."
            do { try update(meeting) } catch { self.error = error.localizedDescription }
        }
        tick()
    }
    private func finished(_ id: UUID, exitCode: Int32) {
        busy = nil; process = nil
        if let activity { ProcessInfo.processInfo.endActivity(activity); self.activity = nil }
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
        guard id != recording, id != busy else { return }
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
