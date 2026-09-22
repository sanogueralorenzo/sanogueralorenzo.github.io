import Foundation
import AppKit
import Observation
import AgentClient
import AgentProtocol

struct ChatMessage: Identifiable {
    let id: UUID
    let role: Role
    var text: String
    var artifacts: [RuntimeArtifact] = []

    enum Role: Equatable { case user, assistant }
}

@MainActor
@Observable final class AppModel {
    enum State: Equatable {
        case needsSetup
        case conversation
    }

    var state: State = .conversation
    var messages: [ChatMessage] = []
    var sessions: [RuntimeSession] = []
    var selectedSessionId: String?
    var input = ""
    var activity = ""
    var isRunning = false
    var isConnected = false
    var connectionError: String?
    var setupStatus: SetupStatus?
    var setupMessage = ""
    var isSettingUp = false
    var scrollRequest = 0

    @ObservationIgnored private let launcher = RuntimeLauncher()
    @ObservationIgnored private var client: RuntimeClient?
    @ObservationIgnored private var observer: Task<Void, Never>?
    @ObservationIgnored private var activeRunId: String?
    @ObservationIgnored private var assistantId: UUID?
    @ObservationIgnored private var submittingSessionId: String?
    @ObservationIgnored private var completedRunId: String?
    @ObservationIgnored private var latestSnapshot: RuntimeSnapshot?

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

    func continueWithChatGPT() async {
        await configure("Opening ChatGPT sign-in…") { client in
            if setupStatus?.authMode == "chatgpt" { return }
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
        guard !text.isEmpty, let client, let selected = selectedSessionId,
              isConnected, !isRunning, submittingSessionId != selected else { return }
        input = ""
        if text == "/new" {
            await newConversation()
            return
        }
        let sessionId = selected
        do {
            guard selectedSessionId == sessionId, isConnected else { return }
            submittingSessionId = sessionId
            completedRunId = nil
            defer { if submittingSessionId == sessionId { submittingSessionId = nil } }
            guard let run = try await client.submit(text: text, sessionId: sessionId) else {
                guard selectedSessionId == sessionId else { return }
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
                messages.append(ChatMessage(id: UUID(), role: .assistant, text: error.localizedDescription))
            }
        }
    }

    func stop() async {
        if let activeRunId { _ = try? await client?.stop(runId: activeRunId) }
    }

    func newConversation() async {
        guard let client else { return }
        do {
            let session = try await client.openSession(fresh: true)
            await selectSession(session.id)
        } catch {
            connectionError = error.localizedDescription
        }
    }

    func selectSession(_ id: String) async {
        guard let client, id != selectedSessionId else { return }
        observer?.cancel()
        selectedSessionId = id
        messages = []
        activeRunId = nil
        submittingSessionId = nil
        assistantId = nil
        latestSnapshot = nil
        completedRunId = nil
        isRunning = false
        activity = ""
        isConnected = false
        do {
            try await connectConversation(client, sessionId: id)
        } catch {
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
                        events = try await reconnected.events(sessionId: sessionId)
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
        if event.type == "session_activity" {
            Task { await refreshSessions() }
            return
        }
        guard envelope.sessionId == selectedSessionId else { return }
        switch event.type {
        case "snapshot":
            if let snapshot = event.snapshot { loadSnapshot(snapshot, scrollToEnd: messages.isEmpty) }
        case "turn":
            activeRunId = envelope.runId
            isRunning = true
            activity = "Thinking"
            let text = event.text?.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayed = text?.isEmpty == false ? text! : event.hasAttachments == true ? "Voice message" : "Message"
            if messages.last?.role != .user || messages.last?.text != displayed {
                messages.append(ChatMessage(id: UUID(), role: .user, text: displayed))
            }
            let id = UUID()
            assistantId = id
            messages.append(ChatMessage(id: id, role: .assistant, text: ""))
            scrollRequest += 1
        case "session":
            Task { await refreshSessions() }
        case "navigate":
            guard let destination = event.session else { break }
            activity = "Opening conversation"
            Task { await selectSession(destination.id) }
        case "text_delta":
            if let id = assistantId { edit(id) { $0.text += event.delta ?? "" } }
        case "artifact":
            if let id = assistantId, let artifact = event.artifact { edit(id) { $0.artifacts.append(artifact) } }
        case "tool_start":
            activity = event.name.map { "Using \($0.replacingOccurrences(of: "_", with: " "))" } ?? "Working"
        case "status":
            activity = event.message ?? "Working"
        case "error":
            if let id = assistantId { edit(id) { if $0.text.isEmpty { $0.text = event.message ?? "Something went wrong." } } }
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
        assistantId = nil
        isRunning = false
        activity = ""
        scrollRequest += 1
    }

    private func loadSnapshot(_ snapshot: RuntimeSnapshot, scrollToEnd: Bool = false) {
        latestSnapshot = snapshot
        sessions = snapshot.sessions
        let previousRunId = activeRunId
        loadTranscript(snapshot.transcript, scrollToEnd: scrollToEnd)
        if let active = snapshot.activeRuns.first(where: { $0.run.sessionId == selectedSessionId }) {
            if let navigation = active.navigation {
                Task { await selectSession(navigation.session.id) }
                return
            }
            let text = active.turn.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayed = !text.isEmpty ? text : active.turn.hasAttachments ? "Voice message" : "Message"
            let storedTurn = active.session != nil && snapshot.transcript?.session.id == active.session?.id &&
                snapshot.transcript?.messages.last(where: { $0.role == "user" || $0.role == "assistant" })?.role == "user"
            if !storedTurn && (messages.last?.role != .user || messages.last?.text != displayed) {
                messages.append(ChatMessage(id: UUID(), role: .user, text: displayed))
            }
            let id = UUID()
            messages.append(ChatMessage(id: id, role: .assistant, text: active.output, artifacts: active.artifacts))
            assistantId = id
            activeRunId = active.run.id
            isRunning = true
            activity = "Thinking"
        } else if let previousRunId, snapshot.lastRuns.contains(where: { $0.id == previousRunId }), submittingSessionId == selectedSessionId {
            completedRunId = previousRunId
        }
    }

    private func loadTranscript(_ transcript: Transcript?, scrollToEnd: Bool = false) {
        if let transcript {
            let visible = transcript.messages.filter { $0.role == "user" || $0.role == "assistant" }
            let unchanged = selectedSessionId == transcript.session.id && messages.count == visible.count &&
                zip(messages, visible).allSatisfy { current, saved in
                    current.role == (saved.role == "user" ? .user : .assistant) && current.text == saved.content
                }
            if !unchanged {
                messages = visible.map { message in
                    ChatMessage(id: UUID(), role: message.role == "user" ? .user : .assistant, text: message.content)
                }
            }
            if scrollToEnd { scrollRequest += 1 }
        } else {
            messages = []
        }
        activeRunId = nil
        assistantId = nil
        isRunning = false
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
}
