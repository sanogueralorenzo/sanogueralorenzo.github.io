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
    @ObservationIgnored private var sessionId: String?
    @ObservationIgnored private var activeRunId: String?
    @ObservationIgnored private var assistantId: UUID?
    @ObservationIgnored private var fresh = false
    @ObservationIgnored private var submitting = false
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
                try await connectConversation(client)
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
        guard !text.isEmpty, let client, isConnected, !isRunning, !submitting else { return }
        input = ""
        if text == "/new" {
            newConversation()
            return
        }
        submitting = true
        completedRunId = nil
        defer { submitting = false }
        do {
            guard let run = try await client.submit(text: text, sessionId: sessionId, fresh: fresh) else {
                activity = "Agent is already working"
                return
            }
            if completedRunId == run.id {
                completedRunId = nil
                return
            }
            if latestSnapshot?.lastRun?.id == run.id && latestSnapshot?.activeRun == nil { return }
            completedRunId = nil
            activeRunId = run.id
            isRunning = true
            activity = "Thinking"
        } catch {
            messages.append(ChatMessage(id: UUID(), role: .assistant, text: error.localizedDescription))
        }
    }

    func stop() async {
        _ = try? await client?.stop()
    }

    func newConversation() {
        guard !isRunning else { return }
        sessionId = nil
        fresh = true
        messages = []
    }

    private func connectConversation(_ client: RuntimeClient) async throws {
        observe(try await client.events())
        isConnected = true
        connectionError = nil
        activity = ""
    }

    private func observe(_ initialEvents: EventStream) {
        observer?.cancel()
        observer = Task {
            var events = initialEvents
            while !Task.isCancelled {
                do {
                    for try await envelope in events { apply(envelope) }
                    if Task.isCancelled { return }
                    throw RuntimeClientError.disconnected
                } catch {
                    if Task.isCancelled { return }
                    isConnected = false
                    activity = "Reconnecting"
                    do {
                        let reconnected = try await launcher.ensureRunning()
                        self.client = reconnected
                        events = try await reconnected.events()
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
            if let previous = sessionId, let next = event.session?.id, previous != next, activeRunId == envelope.runId {
                messages = Array(messages.suffix(2))
            }
            sessionId = event.session?.id
            fresh = false
        case "navigate":
            guard let destination = event.session else { break }
            sessionId = destination.id
            fresh = false
            activity = "Opening conversation"
            Task {
                do {
                    if let transcript = try await client?.transcript(sessionId: destination.id) {
                        loadTranscript(transcript, scrollToEnd: true)
                    }
                } catch {
                    connectionError = error.localizedDescription
                }
            }
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
        if submitting { completedRunId = runId }
        activeRunId = nil
        assistantId = nil
        isRunning = false
        activity = ""
        scrollRequest += 1
    }

    private func loadSnapshot(_ snapshot: RuntimeSnapshot, scrollToEnd: Bool = false) {
        latestSnapshot = snapshot
        let previousRunId = activeRunId
        loadTranscript(snapshot.transcript, scrollToEnd: scrollToEnd)
        if let active = snapshot.activeRun {
            if let navigation = active.navigation {
                sessionId = navigation.session.id
                activeRunId = active.run.id
                isRunning = true
                activity = "Opening conversation"
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
            if let session = active.session { sessionId = session.id }
        } else if let previousRunId, snapshot.lastRun?.id == previousRunId, submitting {
            completedRunId = previousRunId
        }
    }

    private func loadTranscript(_ transcript: Transcript?, scrollToEnd: Bool = false) {
        if let transcript {
            let visible = transcript.messages.filter { $0.role == "user" || $0.role == "assistant" }
            let unchanged = sessionId == transcript.session.id && messages.count == visible.count &&
                zip(messages, visible).allSatisfy { current, saved in
                    current.role == (saved.role == "user" ? .user : .assistant) && current.text == saved.content
                }
            sessionId = transcript.session.id
            if !unchanged {
                messages = visible.map { message in
                    ChatMessage(id: UUID(), role: message.role == "user" ? .user : .assistant, text: message.content)
                }
            }
            if scrollToEnd { scrollRequest += 1 }
        } else {
            sessionId = nil
            messages = []
        }
        activeRunId = nil
        assistantId = nil
        isRunning = false
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
