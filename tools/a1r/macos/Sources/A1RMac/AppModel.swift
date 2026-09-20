import Foundation
import AppKit
import A1RProtocol

struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    let role: Role
    var text: String

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
    private var requestId: String?
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
        isSettingUp = true
        setupMessage = "Checking API key…"
        defer { isSettingUp = false }
        do {
            guard let client else { return }
            try await client.connectOpenAI(key: key)
            setupStatus = try await client.setupStatus()
            setupMessage = ""
            state = .ready
        } catch {
            setupMessage = error.localizedDescription
        }
    }

    func useSavedAPIKey() async {
        guard let client, !isSettingUp else { return }
        isSettingUp = true
        defer { isSettingUp = false }
        do {
            try await client.selectBackend("responses")
            setupStatus = try await client.setupStatus()
            setupMessage = ""
            state = .ready
        } catch {
            setupMessage = error.localizedDescription
        }
    }

    func continueWithChatGPT() async {
        guard let client, !isSettingUp else { return }
        isSettingUp = true
        defer { isSettingUp = false }
        var pendingLoginId: String?
        do {
            if setupStatus?.codex.connected == true {
                try await client.selectBackend("codex")
                setupStatus = try await client.setupStatus()
                setupMessage = "Reusing A1R's private ChatGPT login."
                state = .ready
                return
            }
            setupMessage = "Starting secure ChatGPT sign-in for A1R…"
            let login = try await client.startCodexLogin(mode: "browser")
            pendingLoginId = login.loginId
            setupMessage = "Finish signing in in your browser."
            guard login.type == "chatgpt", let authUrl = login.authUrl else {
                throw RuntimeClientError.badResponse(400, "A1R expected browser login but received another login flow.")
            }
            if let destination = URL(string: authUrl) { NSWorkspace.shared.open(destination) }
            for _ in 0..<300 {
                try await Task.sleep(for: .seconds(1))
                let result = try await client.codexLoginStatus(loginId: login.loginId)
                if result.state == "complete" {
                    pendingLoginId = nil
                    setupStatus = try await client.setupStatus()
                    setupMessage = ""
                    state = .ready
                    return
                }
                if result.state == "failed" {
                    pendingLoginId = nil
                    throw RuntimeClientError.badResponse(400, result.error ?? "ChatGPT sign-in failed.")
                }
            }
            throw RuntimeClientError.badResponse(408, "ChatGPT sign-in timed out. Try again.")
        } catch {
            if let pendingLoginId { try? await client.cancelCodexLogin(loginId: pendingLoginId) }
            setupMessage = error.localizedDescription
            setupStatus = try? await client.setupStatus()
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
        let requestId = UUID().uuidString
        self.requestId = requestId
        do {
            for try await event in client.events(text: text, sessionId: sessionId, requestId: requestId, fresh: fresh) {
                switch event.type {
                case "session":
                    sessionId = event.session?.id
                    fresh = false
                case "text_delta":
                    if let index = messages.firstIndex(where: { $0.id == assistantID }) {
                        messages[index].text += event.delta ?? ""
                    }
                case "tool_start":
                    activity = event.name.map { "Using \($0.replacingOccurrences(of: "_", with: " "))" } ?? "Working"
                case "status":
                    activity = event.message ?? "Working"
                case "error":
                    if let index = messages.firstIndex(where: { $0.id == assistantID }), messages[index].text.isEmpty {
                        messages[index].text = event.message ?? "Something went wrong."
                    }
                default: break
                }
            }
        } catch {
            if let index = messages.firstIndex(where: { $0.id == assistantID }), messages[index].text.isEmpty {
                messages[index].text = error.localizedDescription
            } else if let index = messages.firstIndex(where: { $0.id == assistantID }) {
                messages[index].text += "\n\nInterrupted. Your session is saved."
            }
            self.client = try? await launcher.ensureRunning()
        }
        isRunning = false
        activity = ""
        self.requestId = nil
    }

    func stop() async {
        guard let requestId else { return }
        await client?.cancel(requestId: requestId)
    }

    func newConversation() {
        guard !isRunning else { return }
        sessionId = nil
        fresh = true
        messages = []
    }
}
