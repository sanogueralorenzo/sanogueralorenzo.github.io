import Foundation
import AppKit
import Observation
import AgentClient
import AgentProtocol

struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    let role: Role
    var text: String
    var artifacts: [RuntimeArtifact] = []

    enum Role: Equatable { case user, assistant }
}

@MainActor
@Observable final class AppModel {
    enum State: Equatable {
        case starting
        case needsSetup
        case ready
        case failed(String)
    }

    var state: State = .starting
    var messages: [ChatMessage] = []
    var input = ""
    var activity = ""
    var isRunning = false
    var setupStatus: SetupStatus?
    var setupMessage = ""
    var isSettingUp = false

    @ObservationIgnored private let launcher = RuntimeLauncher()
    @ObservationIgnored private var client: RuntimeClient?
    @ObservationIgnored private var observer: Task<Void, Never>?
    @ObservationIgnored private var sessionId: String?
    @ObservationIgnored private var activeRunId: String?
    @ObservationIgnored private var assistantId: UUID?
    @ObservationIgnored private var fresh = false

    func start() async {
        observer?.cancel()
        activity = ""
        state = .starting
        do {
            let client = try await launcher.ensureRunning()
            self.client = client
            setupStatus = try await client.setupStatus()
            if setupStatus?.configured == true {
                try await loadTranscript(client)
                try await observe(client)
                state = .ready
            } else {
                state = .needsSetup
            }
        } catch {
            state = .failed(error.localizedDescription)
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
        guard !text.isEmpty, let client, !isRunning else { return }
        input = ""
        do {
            guard let run = try await client.submit(text: text, sessionId: sessionId, fresh: fresh) else {
                activity = "Agent is already working"
                return
            }
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

    private func observe(_ initialClient: RuntimeClient) async throws {
        observer?.cancel()
        let initialEvents = try await initialClient.events()
        observer = Task {
            var client = initialClient
            var events = initialEvents
            while !Task.isCancelled {
                do {
                    for try await envelope in events { apply(envelope) }
                    if Task.isCancelled { return }
                    throw RuntimeClientError.disconnected
                } catch {
                    if Task.isCancelled { return }
                    activity = activeRunId == nil ? "Reconnecting" : "Response interrupted; reconnecting"
                    do {
                        client = try await launcher.ensureRunning()
                        self.client = client
                        try await loadTranscript(client)
                        events = try await client.events()
                        activity = ""
                    } catch {
                        state = .failed(error.localizedDescription)
                        return
                    }
                }
            }
        }
    }

    private func apply(_ envelope: RunEnvelope) {
        let event = envelope.event
        switch event.type {
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
        case "session":
            sessionId = event.session?.id
            fresh = false
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
        activeRunId = nil
        assistantId = nil
        isRunning = false
        activity = ""
    }

    private func loadTranscript(_ client: RuntimeClient) async throws {
        if let transcript = try await client.resumeLatest() {
            sessionId = transcript.session.id
            messages = transcript.messages.compactMap { message in
                guard message.role == "user" || message.role == "assistant" else { return nil }
                return ChatMessage(id: UUID(), role: message.role == "user" ? .user : .assistant, text: message.content)
            }
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
            setupStatus = try await client.setupStatus()
            setupMessage = ""
            try await observe(client)
            state = .ready
        } catch {
            setupMessage = error.localizedDescription
        }
    }

    private func edit(_ id: UUID, update: (inout ChatMessage) -> Void) {
        if let index = messages.firstIndex(where: { $0.id == id }) { update(&messages[index]) }
    }
}
