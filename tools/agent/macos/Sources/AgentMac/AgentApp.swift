import SwiftUI
import AgentProtocol

@main
struct AgentApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .frame(minWidth: 620, minHeight: 520)
                .task { await model.start() }
        }
        .defaultSize(width: 720, height: 640)
        .windowToolbarStyle(.unified)
    }
}

struct RootView: View {
    @Bindable var model: AppModel

    var body: some View {
        switch model.state {
        case .starting:
            ProgressView("Starting Agent…")
        case .needsSetup:
            SetupView(model: model)
        case .ready:
            ConversationView(model: model)
        case let .failed(message):
            ContentUnavailableView("Agent needs attention", systemImage: "exclamationmark.circle", description: Text(message))
                .safeAreaInset(edge: .bottom) {
                    Button("Try Again") { Task { await model.start() } }.padding()
                }
        }
    }
}

struct SetupView: View {
    @Bindable var model: AppModel
    @State private var key = ""

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "wind").font(.system(size: 48)).foregroundStyle(.tint)
            Text("Welcome to Agent").font(.largeTitle.weight(.semibold))
            Text("Connect with ChatGPT or an OpenAI API key.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 440)
            Button(model.setupStatus?.codex.connected == true ? "Continue with ChatGPT" : "Sign in with ChatGPT") {
                Task { await model.continueWithChatGPT() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.isSettingUp || model.setupStatus?.codex.installed != true)
            if model.setupStatus?.codex.installed != true {
                Text("Install the Codex CLI to use ChatGPT.").foregroundStyle(.secondary)
            }
            Divider().frame(maxWidth: 420)
            SecureField("OpenAI API key", text: $key).textFieldStyle(.roundedBorder).frame(maxWidth: 420)
            Button("Connect API key") { Task { await model.connectOpenAI(key) } }
                .disabled(!key.hasPrefix("sk-") || model.isSettingUp)
            if model.isSettingUp { ProgressView().controlSize(.small) }
            if !model.setupMessage.isEmpty {
                Text(model.setupMessage).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }.padding(40)
    }
}

struct ConversationView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Agent", systemImage: "wind").font(.headline)
                Spacer()
                Button("New", systemImage: "square.and.pencil") { model.newConversation() }
                    .labelStyle(.titleAndIcon)
                    .disabled(model.isRunning)
            }.padding()
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        if model.messages.isEmpty {
                            ContentUnavailableView("What can I help with?", systemImage: "sparkles", description: Text("Personal help and coding work share the same memory and runtime."))
                                .padding(.top, 80)
                        }
                        ForEach(model.messages) { message in
                            MessageView(message: message).id(message.id)
                        }
                    }.padding(24)
                }
                .onChange(of: model.messages) { _, messages in
                    if let id = messages.last?.id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } }
                }
            }
            if !model.activity.isEmpty {
                HStack { ProgressView().controlSize(.small); Text(model.activity).foregroundStyle(.secondary); Spacer() }
                    .padding(.horizontal, 20).padding(.vertical, 8)
            }
            Divider()
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Message Agent", text: $model.input, axis: .vertical)
                    .textFieldStyle(.plain).lineLimit(1...6)
                    .onSubmit { Task { await model.send() } }
                if model.isRunning {
                    Button("Stop", systemImage: "stop.fill") { Task { await model.stop() } }.labelStyle(.iconOnly)
                } else {
                    Button("Send", systemImage: "arrow.up.circle.fill") { Task { await model.send() } }
                        .labelStyle(.iconOnly).font(.title2).disabled(model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }.padding(16)
        }
    }
}

struct MessageView: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top) {
            if message.role == .user { Spacer(minLength: 80) }
            VStack(alignment: .leading, spacing: 10) {
                if !message.text.isEmpty || message.artifacts.isEmpty {
                    Text(message.text.isEmpty ? "…" : message.text).textSelection(.enabled)
                }
                ForEach(message.artifacts) { artifact in
                    ArtifactView(artifact: artifact)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(message.role == .user ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
            if message.role == .assistant { Spacer(minLength: 80) }
        }
    }
}

struct ArtifactView: View {
    let artifact: RuntimeArtifact

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if artifact.kind == "image", let image = NSImage(contentsOfFile: artifact.path) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 420, maxHeight: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            Button {
                NSWorkspace.shared.open(URL(fileURLWithPath: artifact.path))
            } label: {
                Label(artifact.name, systemImage: artifact.kind == "image" ? "photo" : "doc")
            }
            .buttonStyle(.link)
        }
    }
}
