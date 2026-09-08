import AppKit
import Combine
import UserNotifications
import UniformTypeIdentifiers

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
    @Published private(set) var provider: Provider?
    @Published var elapsed = "0:00"
    let store: MeetingStore
    let support: URL
    let review: Bool
    private var recorder: Recorder?
    private var job: ProcessingJob?
    private var sleepPrevention: NSObjectProtocol?
    var changed: (() -> Void)?
    var openWindow: (() -> Void)?
    var isWorking: Bool { activity != .idle }
    var selectedMeeting: Meeting? { meetings.first { $0.id == selected } }
    init(root: URL, support: URL, review: Bool) throws {
        self.store = try MeetingStore(root: root); self.support = support; self.review = review
        meetings = try store.load()
        selected = meetings.first?.id
        provider = try? Provider.load(from: support.appendingPathComponent("settings.json"))
        if provider == nil { error = "Choose OpenAI or Anthropic in Provider. Your transcript will be sent to that provider through Pi; transcription stays on this Mac." }
    }
    func selectProvider(_ provider: Provider) {
        guard !isWorking else { return }
        do {
            try provider.save(to: support.appendingPathComponent("settings.json"))
            self.provider = provider; error = nil; changed?()
        } catch { self.error = error.localizedDescription }
    }
    private func requireProvider() -> Provider? {
        guard let provider else {
            error = "Choose OpenAI or Anthropic in Provider before sending this transcript to Pi."; openWindow?(); return nil
        }
        return provider
    }
    func tick() {
        if let id = activity.recordingID, var meeting = meetings.first(where: { $0.id == id }) {
            meeting.duration = Date().timeIntervalSince(meeting.date)
            elapsed = Meeting.elapsed(meeting.duration)
            status = "Recording · \(elapsed)"
            if Int(meeting.duration) % 5 == 0 {
                do { try update(meeting) } catch { self.error = "Could not save recording progress: \(error.localizedDescription)" }
            }
        } else if activity.processingID != nil {
            status = job?.progress ?? "Processing…"
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
        guard requireProvider() != nil else { return }
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
        guard let provider = requireProvider() else { return }
        let folder = store.folder(id)
        activity = .processing(id)
        do {
            meeting.state = "processing"; meeting.error = nil
            meeting.processor = provider.label
            try update(meeting)
            let job = ProcessingJob(folder: folder, support: support)
            try job.start(provider: provider) { [weak self] result in self?.finished(id, result: result) }
            self.job = job
            sleepPrevention = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason: "Finishing a meeting note")
        } catch {
            activity = .idle
            meeting.state = "failed"; meeting.error = "Processing could not start: \(error.localizedDescription). Run setup.sh if Moonshine is missing."
            do { try update(meeting) } catch { self.error = error.localizedDescription }
        }
        tick()
    }
    private func finished(_ id: UUID, result: Result<NoteResult, Error>) {
        guard activity == .processing(id) else { return }
        activity = .idle; job = nil
        if let sleepPrevention { ProcessInfo.processInfo.endActivity(sleepPrevention); self.sleepPrevention = nil }
        guard var meeting = meetings.first(where: { $0.id == id }) else { return }
        do {
            let result = try result.get()
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
    func export(_ id: UUID) {
        guard let meeting = meetings.first(where: { $0.id == id }), meeting.state == "ready" else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "Meeting note.txt"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self,
                  let current = self.meetings.first(where: { $0.id == id }) else { return }
            do { try self.store.export(current, to: url) }
            catch { self.error = "Could not export note: \(error.localizedDescription)" }
        }
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
