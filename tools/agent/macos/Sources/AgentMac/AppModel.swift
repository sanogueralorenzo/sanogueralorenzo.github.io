import Foundation
import AppKit
import AVFoundation
import Observation
import AgentClient
import AgentProtocol

struct ChatMessage: Identifiable {
    let id: UUID
    let role: Role
    var text: String
    var artifacts: [RuntimeArtifact] = []

    enum Role: Equatable { case user, assistant, notice }
}

struct VoiceNote {
    let data: Data
    let name: String
    let mimeType: String
}

@MainActor
@Observable final class AppModel {
    static let homeSessionId = "home"

    enum State: Equatable {
        case needsSetup
        case conversation
    }

    var state: State = .conversation
    var messages: [ChatMessage] = []
    var sessions: [RuntimeSession] = []
    var homeEntries: [HomeEntry] = []
    var queuedTasks: [QueuedTask] = []
    var selectedSessionId: String?
    var input = ""
    var voiceNote: VoiceNote?
    var isRecording = false
    var isUploadingVoice = false
    var activity = ""
    var isRunning = false
    var isConnected = false
    var connectionError: String?
    var setupStatus: SetupStatus?
    var setupMessage = ""
    var isSettingUp = false
    var scrollRequest = 0
    var homeScrollPosition: String?

    @ObservationIgnored private let launcher = RuntimeLauncher()
    @ObservationIgnored private var client: RuntimeClient?
    @ObservationIgnored private var observer: Task<Void, Never>?
    @ObservationIgnored private var activeRunId: String?
    @ObservationIgnored private var displayedTurnRunId: String?
    @ObservationIgnored private var assistantId: UUID?
    @ObservationIgnored private var submittingSessionId: String?
    @ObservationIgnored private var completedRunId: String?
    @ObservationIgnored private var optimisticUserId: UUID?
    @ObservationIgnored private var latestSnapshot: RuntimeSnapshot?
    @ObservationIgnored private var homeDraft = ""
    @ObservationIgnored private var recorder: AVAudioRecorder?

    func start() async {
        observer?.cancel()
        activity = ""
        connectionError = nil
        isConnected = false
        do {
            let client = try await launcher.ensureRunning()
            self.client = client
            setupStatus = try await client.setupStatus()
            if setupStatus?.configured == true {
                state = .conversation
                let id = try await client.openSession(preferredSessionId: selectedSessionId).id
                selectedSessionId = id
                try await connectConversation(client, sessionId: id)
            } else {
                state = .needsSetup
            }
        } catch {
            state = .conversation
            connectionError = error.localizedDescription
        }
    }

    func connectOpenAI(_ key: String) async {
        await configure("Connecting API key…") { try await $0.connectOpenAI(key: key) }
    }

    func logout() async {
        guard let client, !isSettingUp else { return }
        isSettingUp = true
        defer { isSettingUp = false }
        do {
            try await client.logout()
            setupMessage = ""
            await start()
        } catch {
            connectionError = error.localizedDescription
        }
    }

    func continueWithChatGPT() async {
        await configure("Opening ChatGPT sign-in…") { client in
            let login = try await client.startCodexLogin(mode: "browser")
            setupMessage = "Finish signing in in your browser."
            guard login.type == "chatgpt", let authUrl = login.authUrl else {
                throw RuntimeClientError.badResponse(400, "Agent expected browser login but received another login flow.")
            }
            if let destination = URL(string: authUrl) { NSWorkspace.shared.open(destination) }
            let result = try await client.waitForCodexLogin(loginId: login.loginId)
            if result.state != "complete" {
                throw RuntimeClientError.badResponse(400, result.error ?? "ChatGPT sign-in failed.")
            }
        }
    }

    func send() async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = voiceNote
        guard !text.isEmpty || note != nil, let client, let selected = selectedSessionId,
              !isUploadingVoice, !(isRunning && selected != Self.homeSessionId && note != nil),
              isConnected, (selected == Self.homeSessionId || isRunning || submittingSessionId != selected) else { return }
        var attachmentIds: [String] = []
        if let note {
            isUploadingVoice = true
            defer { isUploadingVoice = false }
            do {
                attachmentIds = [try await client.uploadVoiceNote(data: note.data, name: note.name, mimeType: note.mimeType)]
            } catch {
                connectionError = error.localizedDescription
                return
            }
        }
        input = ""
        voiceNote = nil
        if text == "/new" && note == nil {
            await newConversation()
            return
        }
        let displayText = text.isEmpty ? "Voice message" : text
        if selected == Self.homeSessionId {
            let requestId = UUID().uuidString
            let optimistic = HomeEntry(
                id: requestId, body: displayText, requests: [HomeRequest(text: displayText, createdAt: ISO8601DateFormatter().string(from: Date()))], state: "routing",
                updatedAt: ISO8601DateFormatter().string(from: Date()))
            homeEntries.append(optimistic)
            homeScrollPosition = requestId
            do {
                guard try await client.submit(text: text, sessionId: selected, requestId: requestId, attachmentIds: attachmentIds) != nil else { return }
            } catch {
                replaceHomeEntry(HomeEntry(
                    id: requestId, body: displayText, summary: error.localizedDescription, state: "failed",
                    updatedAt: ISO8601DateFormatter().string(from: Date())))
                voiceNote = note
            }
            return
        }
        if isRunning {
            do {
                _ = try await client.queue(text: text, sessionId: selected)
            } catch {
                if selectedSessionId == selected {
                    input = input.isEmpty ? text : "\(text)\n\n\(input)"
                    connectionError = error.localizedDescription
                }
            }
            return
        }
        let sessionId = selected
        let optimisticId = UUID()
        optimisticUserId = optimisticId
        appendMessage(ChatMessage(id: optimisticId, role: .user, text: displayText))
        scrollRequest += 1
        do {
            submittingSessionId = sessionId
            completedRunId = nil
            defer { if submittingSessionId == sessionId { submittingSessionId = nil } }
            guard let run = try await client.submit(text: text, sessionId: sessionId, attachmentIds: attachmentIds) else {
                guard selectedSessionId == sessionId else { return }
                messages.removeAll { $0.id == optimisticId }
                if optimisticUserId == optimisticId { optimisticUserId = nil }
                if input.isEmpty { input = text }
                voiceNote = note
                activity = "Agent is already working"
                return
            }
            guard selectedSessionId == sessionId else { return }
            if completedRunId == run.id {
                completedRunId = nil
                return
            }
            if latestSnapshot?.lastRuns.contains(where: { $0.id == run.id }) == true && latestSnapshot?.activeRuns.isEmpty == true { return }
            completedRunId = nil
            activeRunId = run.id
            isRunning = true
            activity = "Thinking"
        } catch {
            if selectedSessionId == sessionId {
                messages.removeAll { $0.id == optimisticId }
                if optimisticUserId == optimisticId { optimisticUserId = nil }
                if input.isEmpty { input = text }
                voiceNote = note
                appendMessage(ChatMessage(id: UUID(), role: .assistant, text: error.localizedDescription))
            }
        }
    }

    func attachVoiceNote(_ url: URL) {
        let types = ["m4a": "audio/mp4", "mp3": "audio/mpeg", "wav": "audio/wav", "ogg": "audio/ogg", "webm": "audio/webm"]
        guard let mimeType = types[url.pathExtension.lowercased()] else {
            connectionError = "Choose an M4A, MP3, WAV, OGG, or WebM voice note."
            return
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            voiceNote = VoiceNote(data: try Data(contentsOf: url), name: url.lastPathComponent, mimeType: mimeType)
        } catch {
            connectionError = error.localizedDescription
        }
    }

    func toggleRecording() async {
        if isRecording {
            let url = recorder?.url
            recorder?.stop()
            recorder = nil
            isRecording = false
            if let url {
                attachVoiceNote(url)
                try? FileManager.default.removeItem(at: url)
            }
            return
        }
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            connectionError = "Allow microphone access to record a voice note."
            return
        }
        do {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("agent-\(UUID().uuidString).m4a")
            let recorder = try AVAudioRecorder(url: url, settings: [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ])
            guard recorder.record() else { throw CocoaError(.fileWriteUnknown) }
            self.recorder = recorder
            isRecording = true
        } catch {
            connectionError = error.localizedDescription
        }
    }

    func stop() async {
        guard selectedSessionId != Self.homeSessionId else { return }
        if let activeRunId { _ = try? await client?.stop(runId: activeRunId) }
    }

    func editQueued(_ task: QueuedTask) async {
        guard let client, selectedSessionId == task.sessionId else { return }
        do {
            let removed = try await client.removeQueued(taskId: task.id, sessionId: task.sessionId)
            input = input.isEmpty ? removed.text : "\(removed.text)\n\n\(input)"
        } catch {
            connectionError = error.localizedDescription
        }
    }

    func removeQueued(_ task: QueuedTask) async {
        guard let client, selectedSessionId == task.sessionId else { return }
        do { _ = try await client.removeQueued(taskId: task.id, sessionId: task.sessionId) }
        catch { connectionError = error.localizedDescription }
    }

    func steerQueued(_ task: QueuedTask) async {
        guard let client, selectedSessionId == task.sessionId, let activeRunId else { return }
        do {
            if !((try await client.steerQueued(taskId: task.id, sessionId: task.sessionId, runId: activeRunId))) {
                connectionError = "That turn has finished. The follow-up remains queued."
            }
        } catch {
            connectionError = error.localizedDescription
        }
    }

    func newConversation() async {
        guard let client else { return }
        do {
            let session = try await client.openSession(fresh: true)
            await selectSession(session.id, notice: "New conversation ready.")
        } catch {
            connectionError = error.localizedDescription
        }
    }

    func selectSession(_ id: String, notice: String? = nil, forwarded: ChatMessage? = nil, expectedRunId: String? = nil) async {
        guard let client, id != selectedSessionId else { return }
        if selectedSessionId == Self.homeSessionId {
            homeDraft = input
        }
        observer?.cancel()
        selectedSessionId = id
        messages = []
        queuedTasks = []
        input = id == Self.homeSessionId ? homeDraft : ""
        if id != Self.homeSessionId {
            if let notice { appendMessage(ChatMessage(id: UUID(), role: .notice, text: notice)) }
            if let forwarded { appendMessage(forwarded) }
        }
        activeRunId = expectedRunId
        displayedTurnRunId = nil
        submittingSessionId = nil
        assistantId = nil
        latestSnapshot = nil
        completedRunId = nil
        isRunning = id != Self.homeSessionId && expectedRunId != nil
        activity = isRunning ? "Thinking" : ""
        isConnected = false
        do {
            try await connectConversation(client, sessionId: id)
        } catch {
            isRunning = false
            activity = ""
            connectionError = error.localizedDescription
        }
    }

    private func connectConversation(_ client: RuntimeClient, sessionId: String) async throws {
        let events = try await client.events(sessionId: sessionId)
        guard selectedSessionId == sessionId else { return }
        observe(events, sessionId: sessionId)
        isConnected = true
        connectionError = nil
        activity = ""
    }

    private func observe(_ initialEvents: EventStream, sessionId: String) {
        observer?.cancel()
        observer = Task {
            var events = initialEvents
            while !Task.isCancelled {
                do {
                    for try await envelope in events {
                        if Task.isCancelled || selectedSessionId != sessionId { return }
                        apply(envelope)
                    }
                    if Task.isCancelled { return }
                    throw RuntimeClientError.disconnected
                } catch {
                    if Task.isCancelled { return }
                    isConnected = false
                    activity = "Reconnecting"
                    do {
                        let reconnected = try await launcher.ensureRunning()
                        self.client = reconnected
                        events = try await reconnected.events(sessionId: sessionId, runId: activeRunId)
                        isConnected = true
                        connectionError = nil
                        activity = ""
                    } catch {
                        if Task.isCancelled { return }
                        activity = ""
                        connectionError = error.localizedDescription
                        return
                    }
                }
            }
        }
    }

    private func apply(_ envelope: RunEnvelope) {
        let event = envelope.event
        if event.type == "home_entry", let entry = event.entry {
            replaceHomeEntry(entry)
            if selectedSessionId == Self.homeSessionId { homeScrollPosition = entry.id }
            return
        }
        if event.type == "home_entry_removed", let id = event.id {
            homeEntries.removeAll { $0.id == id }
            return
        }
        if event.type == "session_activity" {
            Task { await refreshSessions() }
            return
        }
        guard envelope.sessionId == selectedSessionId else { return }
        switch event.type {
        case "snapshot":
            if let snapshot = event.snapshot { loadSnapshot(snapshot) }
        case "queue":
            queuedTasks = event.tasks ?? []
        case "turn":
            if displayedTurnRunId == envelope.runId {
                if let text = event.text, let index = messages.lastIndex(where: { $0.role == .user }) {
                    messages[index].text = text
                }
                break
            }
            displayedTurnRunId = envelope.runId
            optimisticUserId = nil
            activeRunId = envelope.runId
            isRunning = true
            activity = "Thinking"
            appendUserTurn(event.text, hasAttachments: event.hasAttachments == true)
            let id = UUID()
            assistantId = id
            appendMessage(ChatMessage(id: id, role: .assistant, text: ""))
            scrollRequest += 1
        case "steer":
            appendUserTurn(event.text, hasAttachments: false)
            scrollRequest += 1
        case "session":
            Task { await refreshSessions() }
        case "navigate":
            guard let destination = event.session else { break }
            activity = "Opening conversation"
            let forwarded = optimisticUserId.flatMap { id in messages.first(where: { $0.id == id }) }
            if let optimisticUserId { messages.removeAll { $0.id == optimisticUserId } }
            optimisticUserId = nil
            Task { await selectSession(destination.id, notice: "Opened “\(destination.title ?? "Conversation")”.", forwarded: event.continues == true ? forwarded : nil, expectedRunId: event.continues == true ? envelope.runId : nil) }
        case "text_delta":
            if let id = assistantId { edit(id) { $0.text += event.delta ?? "" } }
        case "artifact":
            if let id = assistantId, let artifact = event.artifact { edit(id) { $0.artifacts.append(artifact) } }
        case "tool_start":
            activity = event.name.map { "Using \($0.replacingOccurrences(of: "_", with: " "))" } ?? "Working"
        case "status":
            activity = event.message ?? "Working"
        case "error":
            if activeRunId == nil { activeRunId = envelope.runId }
            if let id = assistantId { edit(id) { if $0.text.isEmpty { $0.text = event.message ?? "Something went wrong." } } }
            else { appendMessage(ChatMessage(id: UUID(), role: .assistant, text: event.message ?? "Something went wrong.")) }
            finish(envelope.runId)
        case "done":
            finish(envelope.runId)
        default:
            break
        }
    }

    private func finish(_ runId: String) {
        guard activeRunId == runId else { return }
        if submittingSessionId == selectedSessionId { completedRunId = runId }
        activeRunId = nil
        displayedTurnRunId = nil
        assistantId = nil
        optimisticUserId = nil
        isRunning = false
        activity = ""
        scrollRequest += 1
    }

    private func loadSnapshot(_ snapshot: RuntimeSnapshot) {
        latestSnapshot = snapshot
        sessions = snapshot.sessions
        homeEntries = snapshot.homeEntries
        queuedTasks = snapshot.queuedTasks
        if selectedSessionId == Self.homeSessionId {
            homeScrollPosition = homeEntries.last?.id
            messages = []
            activeRunId = nil
            isRunning = false
            activity = ""
            return
        }
        if messages.isEmpty, let transcript = snapshot.transcript, transcript.session.id == selectedSessionId {
            messages = transcript.messages.filter { $0.role == "user" || $0.role == "assistant" }.map {
                ChatMessage(id: UUID(), role: $0.role == "user" ? .user : .assistant, text: $0.content)
            }
        }
        let previousRunId = activeRunId
        if let active = snapshot.activeRuns.first(where: { $0.run.sessionId == selectedSessionId }) {
            if let navigation = active.navigation, navigation.session.id != selectedSessionId {
                Task { await selectSession(navigation.session.id, notice: "Opened “\(navigation.session.title ?? "Conversation")”.", expectedRunId: navigation.continues == true ? active.run.id : nil) }
                return
            }
            if active.navigation?.continues == false {
                activeRunId = active.run.id
                isRunning = true
                activity = "Opening conversation"
                return
            }
            if displayedTurnRunId != active.run.id {
                appendUserTurn(active.turn.text, hasAttachments: active.turn.hasAttachments)
                let id = UUID()
                appendMessage(ChatMessage(id: id, role: .assistant, text: active.output, artifacts: active.artifacts))
                assistantId = id
            } else if let id = assistantId {
                edit(id) { $0.text = active.output; $0.artifacts = active.artifacts }
            }
            activeRunId = active.run.id
            displayedTurnRunId = active.run.id
            isRunning = true
            activity = "Thinking"
        } else if let previousRunId, snapshot.lastRuns.contains(where: { $0.id == previousRunId }) {
            if submittingSessionId == selectedSessionId { completedRunId = previousRunId }
            if let transcript = snapshot.transcript, transcript.session.id == selectedSessionId {
                if displayedTurnRunId != previousRunId, let user = transcript.messages.last(where: { $0.role == "user" }) {
                    appendUserTurn(user.content, hasAttachments: false)
                }
                if let answer = transcript.messages.last, answer.role == "assistant" {
                    if let id = assistantId { edit(id) { $0.text = answer.content } }
                    else { appendMessage(ChatMessage(id: UUID(), role: .assistant, text: answer.content)) }
                }
            }
            finish(previousRunId)
        } else if previousRunId != nil {
            activeRunId = nil
            isRunning = false
            activity = ""
        }
    }

    private func refreshSessions() async {
        if let updated = try? await client?.sessions() { sessions = updated }
    }

    private func configure(_ message: String = "", action: (RuntimeClient) async throws -> Void) async {
        guard let client, !isSettingUp else { return }
        isSettingUp = true
        setupMessage = message
        defer { isSettingUp = false }
        do {
            try await action(client)
            setupMessage = ""
            await start()
        } catch {
            setupMessage = error.localizedDescription
        }
    }

    private func edit(_ id: UUID, update: (inout ChatMessage) -> Void) {
        if let index = messages.firstIndex(where: { $0.id == id }) { update(&messages[index]) }
    }

    private func appendMessage(_ message: ChatMessage) {
        messages.append(message)
        if messages.count > 200 { messages.removeFirst(messages.count - 200) }
    }

    private func replaceHomeEntry(_ entry: HomeEntry) {
        if let index = homeEntries.firstIndex(where: { $0.id == entry.id }) { homeEntries[index] = entry }
        else { homeEntries.append(entry) }
        homeEntries.sort { $0.updatedAt < $1.updatedAt }
        if homeEntries.count > 200 { homeEntries.removeFirst(homeEntries.count - 200) }
    }

    private func appendUserTurn(_ text: String?, hasAttachments: Bool) {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayed = (trimmed?.isEmpty == false ? trimmed : nil) ?? (hasAttachments ? "Voice message" : "Message")
        if messages.last?.role != .user || messages.last?.text != displayed {
            appendMessage(ChatMessage(id: UUID(), role: .user, text: displayed))
        }
    }
}
