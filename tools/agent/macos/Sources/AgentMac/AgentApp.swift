import SwiftUI
import AgentProtocol

private enum AgentStyle {
    static let canvas = Color(red: 0.965, green: 0.949, blue: 0.921)
    static let surface = Color(red: 0.925, green: 0.910, blue: 0.882)
    static let userSurface = Color(red: 0.91, green: 0.87, blue: 0.80)
    static let graphite = Color(red: 0.18, green: 0.17, blue: 0.16)
    static let muted = Color(red: 0.45, green: 0.43, blue: 0.40)
    static let line = graphite.opacity(0.13)
    static let clay = Color(red: 0.73, green: 0.38, blue: 0.20)
    static let sage = Color(red: 0.61, green: 0.67, blue: 0.57)
    static let contentWidth: CGFloat = 560
}

@main
struct AgentApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("Agent") {
            RootView(model: model)
                .frame(minWidth: 620, minHeight: 520)
                .task { await model.start() }
                .preferredColorScheme(.light)
                .tint(AgentStyle.clay)
        }
        .defaultSize(width: 720, height: 640)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Conversation") { model.newConversation() }
                    .keyboardShortcut("n")
                    .disabled(model.isRunning)
            }
        }
    }
}

struct RootView: View {
    @Bindable var model: AppModel

    var body: some View {
        Group {
            switch model.state {
            case .needsSetup:
                SetupView(model: model)
            case .conversation:
                ConversationView(model: model)
            }
        }
        .foregroundStyle(AgentStyle.graphite)
        .background(AgentStyle.canvas.ignoresSafeArea())
    }
}

struct SetupView: View {
    @Bindable var model: AppModel
    @State private var key = ""

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Circle()
                .fill(AgentStyle.clay)
                .frame(width: 12, height: 12)
            VStack(spacing: 8) {
                Text("Agent")
                    .font(.system(size: 28, weight: .semibold))
                Text("Connect once, then continue from anywhere.")
                    .foregroundStyle(AgentStyle.muted)
            }
            Button(model.setupStatus?.codex.connected == true ? "Continue with ChatGPT" : "Sign in with ChatGPT") {
                Task { await model.continueWithChatGPT() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.isSettingUp || model.setupStatus?.codex.installed != true)
            if model.setupStatus?.codex.installed != true {
                Text("Codex CLI is required for ChatGPT.")
                    .font(.caption)
                    .foregroundStyle(AgentStyle.muted)
            }
            HStack(spacing: 12) {
                Rectangle().fill(AgentStyle.line).frame(height: 1)
                Text("or").font(.caption).foregroundStyle(AgentStyle.muted)
                Rectangle().fill(AgentStyle.line).frame(height: 1)
            }
            .frame(maxWidth: 360)
            HStack(spacing: 10) {
                SecureField("OpenAI API key", text: $key)
                    .textFieldStyle(.plain)
                Button("Connect") { Task { await model.connectOpenAI(key) } }
                    .buttonStyle(.bordered)
                    .disabled(!key.hasPrefix("sk-") || model.isSettingUp)
            }
            .padding(.horizontal, 14)
            .frame(width: 360, height: 44)
            .background(.white.opacity(0.42), in: RoundedRectangle(cornerRadius: 13))
            .overlay { RoundedRectangle(cornerRadius: 13).stroke(AgentStyle.line) }
            if model.isSettingUp { ProgressView().controlSize(.small) }
            if !model.setupMessage.isEmpty {
                Text(model.setupMessage)
                    .font(.caption)
                    .foregroundStyle(AgentStyle.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }
            Spacer()
        }
        .padding(40)
    }
}

struct ConversationView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        if model.messages.isEmpty { EmptyConversationView() }
                        ForEach(model.messages) { message in
                            MessageView(message: message).id(message.id)
                        }
                    }
                    .frame(maxWidth: AgentStyle.contentWidth)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
                }
                .onChange(of: model.messages) { _, messages in
                    if let id = messages.last?.id { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .bottom) } }
                }
            }
            if !model.activity.isEmpty { ActivityLine(text: model.activity) }
            if let error = model.connectionError {
                ConnectionError(message: error) { Task { await model.start() } }
            }
            MessageComposer(model: model)
        }
        .toolbar {
            ToolbarSpacer(.flexible)
            ToolbarItem(placement: .primaryAction) {
                Circle()
                    .fill(model.isConnected ? AgentStyle.sage : AgentStyle.muted.opacity(0.45))
                    .frame(width: 12, height: 12)
                    .accessibilityLabel(model.isConnected ? "Connected" : "Reconnecting")
                    .allowsHitTesting(false)
            }
        }
        .toolbarBackground(AgentStyle.canvas, for: .windowToolbar)
    }
}

private struct EmptyConversationView: View {
    var body: some View {
        VStack(spacing: 12) {
            Circle().fill(AgentStyle.clay).frame(width: 10, height: 10)
            Text("How can I help?")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(AgentStyle.muted)
        }
        .frame(maxWidth: .infinity, minHeight: 280)
    }
}

private struct ActivityLine: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.mini)
            Text(text).font(.caption).foregroundStyle(AgentStyle.muted)
            Spacer()
        }
        .frame(maxWidth: AgentStyle.contentWidth)
        .padding(.horizontal, 28)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
    }
}

private struct ConnectionError: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(message).font(.caption).foregroundStyle(AgentStyle.muted).lineLimit(2)
            Spacer()
            Button("Retry", action: retry).buttonStyle(.borderless)
        }
        .frame(maxWidth: AgentStyle.contentWidth)
        .padding(.horizontal, 28)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
    }
}

private struct MessageComposer: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Message Agent", text: $model.input, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .frame(minHeight: 30, alignment: .center)
                .disabled(!model.isConnected)
                .onSubmit { Task { await model.send() } }
            Button {
                Task { model.isRunning ? await model.stop() : await model.send() }
            } label: {
                Image(systemName: model.isRunning ? "stop.fill" : "arrow.up")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(model.isRunning ? AgentStyle.clay : AgentStyle.graphite, in: Circle())
            }
            .buttonStyle(.plain)
            .help(model.isRunning ? "Stop" : "Send")
            .disabled(!model.isRunning && (!model.isConnected || model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
        }
        .padding(10)
        .padding(.leading, 4)
        .frame(maxWidth: AgentStyle.contentWidth)
        .background(.white.opacity(0.38), in: RoundedRectangle(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).stroke(AgentStyle.line) }
        .shadow(color: AgentStyle.graphite.opacity(0.04), radius: 10, y: 4)
        .padding(.horizontal, 28)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity)
    }
}

struct MessageView: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if message.role == .user { Spacer(minLength: 72) }
            VStack(alignment: .leading, spacing: 10) {
                if !message.text.isEmpty || message.artifacts.isEmpty {
                    Text(message.text.isEmpty ? "…" : message.text)
                        .font(.system(size: 15))
                        .lineSpacing(3)
                        .textSelection(.enabled)
                }
                ForEach(message.artifacts) { artifact in
                    ArtifactView(artifact: artifact)
                }
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 11)
            .background(message.role == .user ? AgentStyle.userSurface : AgentStyle.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                if message.role == .assistant {
                    RoundedRectangle(cornerRadius: 14).stroke(AgentStyle.line.opacity(0.55))
                }
            }
            if message.role == .assistant { Spacer(minLength: 72) }
        }
    }
}

struct ArtifactView: View {
    let artifact: RuntimeArtifact

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if artifact.kind == "image", let image = NSImage(contentsOfFile: artifact.path) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 420, maxHeight: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            Button {
                NSWorkspace.shared.open(URL(fileURLWithPath: artifact.path))
            } label: {
                Label(artifact.name, systemImage: artifact.kind == "image" ? "photo" : "doc")
                    .font(.caption)
            }
            .buttonStyle(.link)
        }
    }
}
