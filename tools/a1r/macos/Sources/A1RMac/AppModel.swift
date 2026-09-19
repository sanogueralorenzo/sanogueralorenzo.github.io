import Foundation
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
        case needsOpenAI
        case ready
        case failed(String)
    }

    @Published var state: State = .starting
    @Published var messages: [ChatMessage] = []
    @Published var input = ""
    @Published var activity = ""
    @Published var isRunning = false

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
            if try await client.setupStatus().openAIConfigured {
                if let transcript = try await client.resumeLatest() {
                    sessionId = transcript.session.id
                    messages = transcript.messages.compactMap { message in
                        guard message.role == "user" || message.role == "assistant" else { return nil }
                        return ChatMessage(id: UUID(), role: message.role == "user" ? .user : .assistant, text: message.content)
                    }
                }
                state = .ready
            } else {
                state = .needsOpenAI
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func connectOpenAI(_ key: String) async {
        do {
            guard let client else { return }
            try await client.connectOpenAI(key: key)
            state = .ready
        } catch {
            state = .failed(error.localizedDescription)
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
