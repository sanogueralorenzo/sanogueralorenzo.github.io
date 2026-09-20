import Foundation
import AppKit
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
final class AppModel: ObservableObject {
    enum State: Equatable {
        case starting
        case needsSetup
        case ready
        case failed(String)
    }

    @Published var state: State = .starting
    @Published var messages: [ChatMessage] = []
    @Published var input = ""
    @Published var activity = ""
    @Published var isRunning = false
    @Published var setupStatus: SetupStatus?
    @Published var setupMessage = ""
    @Published var isSettingUp = false

    private let launcher = RuntimeLauncher()
    private var client: RuntimeClient?
    private var sessionId: String?
    private var fresh = false

    func start() async {
        state = .starting
        do {
            let client = try await launcher.ensureRunning()
            self.client = client
            let setup = try await client.setupStatus()
            setupStatus = setup
            if setup.configured {
                if let transcript = try await client.resumeLatest() {
                    sessionId = transcript.session.id
                    messages = transcript.messages.compactMap { message in
                        guard message.role == "user" || message.role == "assistant" else { return nil }
                        return ChatMessage(id: UUID(), role: message.role == "user" ? .user : .assistant, text: message.content)
                    }
                }
                state = .ready
            } else {
                state = .needsSetup
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func connectOpenAI(_ key: String) async {
        await configure("Checking API key…") { try await $0.connectOpenAI(key: key) }
    }

    func useSavedAPIKey() async {
        await configure { try await $0.selectBackend("responses") }
    }

    func continueWithChatGPT() async {
        await configure("Opening ChatGPT sign-in…") { client in
            if setupStatus?.codex.connected == true {
                try await client.selectBackend("codex")
                return
            }
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
        isRunning = true
        activity = "Thinking"
        let assistantID = UUID()
        messages.append(ChatMessage(id: UUID(), role: .user, text: text))
        messages.append(ChatMessage(id: assistantID, role: .assistant, text: ""))
        do {
            let events = try await client.events(text: text, sessionId: sessionId, fresh: fresh)
            for try await event in events {
                switch event.type {
                case "session":
                    sessionId = event.session?.id
                    fresh = false
                case "text_delta":
                    edit(assistantID) { $0.text += event.delta ?? "" }
                case "artifact":
                    if let artifact = event.artifact { edit(assistantID) { $0.artifacts.append(artifact) } }
                case "tool_start":
                    activity = event.name.map { "Using \($0.replacingOccurrences(of: "_", with: " "))" } ?? "Working"
                case "status":
                    activity = event.message ?? "Working"
                case "error":
                    edit(assistantID) { if $0.text.isEmpty { $0.text = event.message ?? "Something went wrong." } }
                default: break
                }
            }
        } catch {
            edit(assistantID) {
                $0.text = $0.text.isEmpty ? error.localizedDescription : $0.text + "\n\nInterrupted. Your session is saved."
            }
            self.client = try? await launcher.ensureRunning()
        }
        isRunning = false
        activity = ""
    }

    func stop() async {
        _ = await client?.cancel()
    }

    func newConversation() {
        guard !isRunning else { return }
        sessionId = nil
        fresh = true
        messages = []
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
            state = .ready
        } catch {
            setupMessage = error.localizedDescription
        }
    }

    private func edit(_ id: UUID, update: (inout ChatMessage) -> Void) {
        if let index = messages.firstIndex(where: { $0.id == id }) { update(&messages[index]) }
    }
}
