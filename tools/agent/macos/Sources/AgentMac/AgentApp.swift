import SwiftUI
import AgentProtocol
import UniformTypeIdentifiers

private enum AgentStyle {
    private static func adaptive(light: (CGFloat, CGFloat, CGFloat), dark: (CGFloat, CGFloat, CGFloat)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let rgb = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        })
    }

    static let canvas = adaptive(light: (0.965, 0.949, 0.921), dark: (0.016, 0.016, 0.016))
    static let surface = adaptive(light: (0.925, 0.910, 0.882), dark: (0.16, 0.155, 0.145))
    static let userSurface = adaptive(light: (0.055, 0.45, 0.90), dark: (0.055, 0.45, 0.90))
    static let assistantSurface = adaptive(light: (0.11, 0.11, 0.11), dark: (0.11, 0.11, 0.11))
    static let graphite = adaptive(light: (0.18, 0.17, 0.16), dark: (0.92, 0.90, 0.87))
    static let muted = adaptive(light: (0.45, 0.43, 0.40), dark: (0.69, 0.67, 0.64))
    static let line = graphite.opacity(0.13)
    static let clay = adaptive(light: (0.73, 0.38, 0.20), dark: (0.70, 0.34, 0.19))
    static let inputSurface = adaptive(light: (0.98, 0.97, 0.95), dark: (0.11, 0.11, 0.11))
    static let sendSurface = adaptive(light: (0.18, 0.17, 0.16), dark: (0.70, 0.34, 0.19))
    static let contentMaxWidth: CGFloat = 820
    static let messageMaxWidth: CGFloat = 640
    static let messageGutter: CGFloat = 48
    static let edgePadding: CGFloat = 20
    static let bubbleRadius: CGFloat = 20
}

@main
struct AgentApp: App {
    @State private var model = AppModel()
    @AppStorage("windowPinned") private var windowPinned = false

    var body: some Scene {
        WindowGroup("Agent") {
            RootView(model: model, windowPinned: $windowPinned)
                .frame(minWidth: 420, minHeight: 360)
                .task { await model.start() }
                .tint(AgentStyle.clay)
        }
        .defaultSize(width: 720, height: 640)
        .windowLevel(windowPinned ? .floating : .normal)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Conversation") { Task { await model.newConversation() } }
                    .keyboardShortcut("n")
            }
        }
    }
}

struct RootView: View {
    @Bindable var model: AppModel
    @Binding var windowPinned: Bool
    @State private var showingLogin = false

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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if model.setupStatus?.configured == true {
                        Button("Log Out") { Task { await model.logout() } }
                            .disabled(model.isSettingUp)
                    } else {
                        Button("Log In…") { showingLogin = true }
                    }
                    Divider()
                    Button(windowPinned ? "Unpin Window" : "Pin Window") {
                        windowPinned.toggle()
                        (NSApp.keyWindow ?? NSApp.mainWindow)?.level = windowPinned ? .floating : .normal
                    }
                    Divider()
                    Button("Quit Agent") { NSApp.terminate(nil) }
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Settings")
            }
        }
        .sheet(isPresented: $showingLogin) {
            SignInView(model: model)
        }
        .onChange(of: model.setupStatus?.configured) { _, configured in
            if configured == true { showingLogin = false }
        }
    }
}

struct SetupView: View {
    @Bindable var model: AppModel

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
            SignInControls(model: model)
            Spacer()
        }
        .padding(40)
    }
}

private struct SignInView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Log In").font(.title2.weight(.semibold))
            SignInControls(model: model)
            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 420)
        .foregroundStyle(AgentStyle.graphite)
        .background(AgentStyle.canvas)
    }
}

private struct SignInControls: View {
    @Bindable var model: AppModel
    @State private var key = ""

    var body: some View {
        VStack(spacing: 16) {
            Button("Sign in with ChatGPT") {
                Task { await model.continueWithChatGPT() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.isSettingUp || model.setupStatus?.codex.installed != true)
            if model.setupStatus?.codex.installed == false {
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
                Button("Connect") {
                    let submittedKey = key
                    key = ""
                    Task { await model.connectOpenAI(submittedKey) }
                }
                    .buttonStyle(.bordered)
                    .disabled(!key.hasPrefix("sk-") || model.isSettingUp || model.setupStatus?.codex.installed != true)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: 360, minHeight: 44)
            .background(AgentStyle.inputSurface, in: RoundedRectangle(cornerRadius: 13))
            .overlay { RoundedRectangle(cornerRadius: 13).stroke(AgentStyle.line) }
            if model.isSettingUp { ProgressView().controlSize(.small) }
            if !model.setupMessage.isEmpty {
                Text(model.setupMessage)
                    .font(.caption)
                    .foregroundStyle(AgentStyle.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }
        }
    }
}

struct ConversationView: View {
    @Bindable var model: AppModel
    @State private var scrollPosition: String?

    var body: some View {
        VStack(spacing: 0) {
            if model.selectedSessionId == AppModel.homeSessionId {
                if model.homeEntries.isEmpty {
                    Spacer(minLength: 0)
                    EmptyConversationView()
                    Spacer(minLength: 0)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 30) {
                            ForEach(model.homeEntries) { entry in
                                HomeEntryView(entry: entry) {
                                    if let sessionId = entry.sessionId { Task { await model.selectSession(sessionId) } }
                                }
                                .id(entry.id)
                            }
                        }
                        .scrollTargetLayout()
                        .frame(maxWidth: AgentStyle.contentMaxWidth)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, AgentStyle.edgePadding)
                        .padding(.vertical, 24)
                    }
                    .scrollPosition(id: $model.homeScrollPosition, anchor: .bottom)
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 20) {
                            if model.messages.isEmpty { EmptyConversationView() }
                            ForEach(model.messages) { message in
                                MessageView(message: message).id(message.id.uuidString)
                            }
                        }
                        .scrollTargetLayout()
                        .frame(maxWidth: AgentStyle.contentMaxWidth)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, AgentStyle.edgePadding)
                        .padding(.vertical, 24)
                    }
                    .scrollPosition(id: $scrollPosition, anchor: .top)
                    .onChange(of: model.scrollRequest) {
                        if let id = model.messages.last?.id { proxy.scrollTo(id.uuidString, anchor: .bottom) }
                    }
                }
            }
            if model.selectedSessionId != AppModel.homeSessionId && !model.activity.isEmpty { ActivityLine(text: model.activity) }
            if let error = model.connectionError {
                ConnectionError(message: error) { Task { await model.start() } }
            }
            if model.selectedSessionId != AppModel.homeSessionId && !model.queuedTasks.isEmpty {
                QueuedFollowUpsView(model: model)
            }
            MessageComposer(model: model)
        }
        .toolbar {
            if model.selectedSessionId != AppModel.homeSessionId {
                ToolbarItem(placement: .navigation) {
                    Button { Task { await model.selectSession(AppModel.homeSessionId) } } label: {
                        Label("Home", systemImage: "chevron.left")
                    }
                    .help("Back to Home")
                }
            }
            ToolbarItem(placement: .principal) {
                Text(model.selectedSessionId == AppModel.homeSessionId ? "Agent" : model.sessions.first(where: { $0.id == model.selectedSessionId })?.title ?? "Agent")
                    .lineLimit(1)
                    .frame(maxWidth: 220)
            }
        }
        .toolbarBackground(AgentStyle.canvas, for: .windowToolbar)
        .background {
            EscapeKeyMonitor { window in
                if model.selectedSessionId == AppModel.homeSessionId {
                    window.performClose(nil)
                } else if model.selectedSessionId != nil {
                    Task { await model.selectSession(AppModel.homeSessionId) }
                }
            }
        }
    }
}

private struct EscapeKeyMonitor: NSViewRepresentable {
    let onEscape: (NSWindow) -> Void

    func makeNSView(context: Context) -> EscapeMonitorView {
        EscapeMonitorView()
    }

    func updateNSView(_ view: EscapeMonitorView, context: Context) {
        view.onEscape = onEscape
    }

    static func dismantleNSView(_ view: EscapeMonitorView, coordinator: ()) {
        view.stopMonitoring()
    }
}

private final class EscapeMonitorView: NSView {
    var onEscape: ((NSWindow) -> Void)?
    private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopMonitoring()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window, event.window === window,
                  event.keyCode == 53,
                  event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty else { return event }
            self.onEscape?(window)
            return nil
        }
    }

    func stopMonitoring() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

private struct HomeEntryView: View {
    let entry: HomeEntry
    let open: () -> Void

    private var isWorking: Bool { entry.state == "routing" || entry.state == "working" }
    private var statusSymbol: String? {
        switch entry.state {
        case "ready": "👍"
        case "needs_input": "💬"
        case "failed": "⚠️"
        default: nil
        }
    }

    @ViewBuilder private var statusBadge: some View {
        if isWorking || statusSymbol != nil {
            let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
            ZStack {
                shape.fill(AgentStyle.assistantSurface)
                if isWorking {
                    ProgressView().controlSize(.mini).scaleEffect(0.8)
                } else if let symbol = statusSymbol {
                    Text(symbol).font(.system(size: 13))
                }
            }
            .frame(width: 34, height: 30)
            .overlay { shape.stroke(AgentStyle.canvas, lineWidth: 4) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(isWorking ? "Working" : entry.state == "needs_input" ? "Needs your reply" : entry.state == "failed" ? "Failed" : "Ready")
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Spacer(minLength: AgentStyle.messageGutter)
            Button(action: open) {
                VStack(alignment: .leading, spacing: 5) {
                    if let title = entry.title {
                        Text(title).font(.system(size: 15))
                    }
                    Text(entry.summary ?? entry.body)
                        .font(.system(size: 15))
                        .lineSpacing(3)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: AgentStyle.messageMaxWidth, alignment: .leading)
                .padding(.horizontal, 17)
                .padding(.vertical, 13)
                .foregroundStyle(.white)
                .background(AgentStyle.userSurface, in: RoundedRectangle(cornerRadius: AgentStyle.bubbleRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(entry.sessionId == nil)
            .overlay(alignment: .bottomTrailing) {
                statusBadge
                    .offset(x: -6, y: 20)
                    .allowsHitTesting(false)
            }
        }
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
        .frame(maxWidth: AgentStyle.contentMaxWidth)
        .padding(.horizontal, AgentStyle.edgePadding)
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
        .frame(maxWidth: AgentStyle.contentMaxWidth)
        .padding(.horizontal, AgentStyle.edgePadding)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
    }
}

private struct MessageComposer: View {
    @Bindable var model: AppModel
    @State private var importingAudio = false
    private var hasText: Bool { !model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var hasContent: Bool { hasText || model.voiceNote != nil }
    private var canStop: Bool { model.selectedSessionId != AppModel.homeSessionId && model.isRunning && !hasContent }

    var body: some View {
        VStack(spacing: 8) {
            if let note = model.voiceNote {
                HStack(spacing: 8) {
                    Image(systemName: "waveform")
                    Text(note.name).lineLimit(1)
                    Button { model.voiceNote = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain)
                        .help("Remove voice note")
                    Spacer()
                }
                .font(.caption)
                .padding(.horizontal, 18)
            } else if model.isRecording {
                Text("Recording… Tap the microphone to finish")
                    .font(.caption)
                    .foregroundStyle(AgentStyle.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
            }
            HStack(alignment: .bottom, spacing: 10) {
                Button { importingAudio = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(AgentStyle.graphite)
                        .frame(width: 36, height: 38)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Attach voice note")
                .disabled(!model.isConnected || model.isUploadingVoice || (model.isRunning && model.selectedSessionId != AppModel.homeSessionId))

                TextField("Message", text: $model.input, axis: .vertical)
                    .font(.system(size: 16))
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
                    .frame(minHeight: 38, alignment: .center)
                    .disabled(!model.isConnected || model.isUploadingVoice)
                    .onSubmit { Task { await model.send() } }

                if hasContent || canStop {
                    Button {
                        Task { canStop ? await model.stop() : await model.send() }
                    } label: {
                        Image(systemName: canStop ? "stop.fill" : "arrow.up")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(canStop ? AgentStyle.clay : AgentStyle.userSurface, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help(canStop ? "Stop" : model.isRunning && model.selectedSessionId != AppModel.homeSessionId ? "Queue follow-up" : "Send")
                    .disabled(!model.isConnected || model.isUploadingVoice || (model.voiceNote != nil && model.isRunning && model.selectedSessionId != AppModel.homeSessionId))
                } else {
                    Button { Task { await model.toggleRecording() } } label: {
                        Image(systemName: model.isRecording ? "stop.fill" : "mic")
                            .font(.system(size: 20))
                            .foregroundStyle(model.isRecording ? AgentStyle.clay : AgentStyle.muted)
                            .frame(width: 38, height: 38)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(model.isRecording ? "Finish voice note" : "Record voice note")
                    .disabled(!model.isConnected)
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 8)
            .padding(.vertical, 8)
            .frame(maxWidth: AgentStyle.contentMaxWidth)
            .background(AgentStyle.inputSurface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .fileImporter(isPresented: $importingAudio, allowedContentTypes: [.audio]) { result in
            switch result {
            case let .success(url): model.attachVoiceNote(url)
            case let .failure(error): model.connectionError = error.localizedDescription
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity)
    }
}

private struct QueuedFollowUpsView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Queued follow-ups")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AgentStyle.muted)
            ForEach(model.queuedTasks) { task in
                HStack(alignment: .top, spacing: 12) {
                    Text(task.text)
                        .font(.system(size: 13))
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Edit") { Task { await model.editQueued(task) } }
                    Button("Remove") { Task { await model.removeQueued(task) } }
                    Button("Steer") { Task { await model.steerQueued(task) } }
                        .disabled(!model.isRunning)
                }
                .buttonStyle(.borderless)
                .font(.caption)
                if task.id != model.queuedTasks.last?.id { Divider() }
            }
        }
        .padding(12)
        .frame(maxWidth: AgentStyle.contentMaxWidth, alignment: .leading)
        .background(AgentStyle.surface, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, AgentStyle.edgePadding)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
    }
}

struct MessageView: View {
    let message: ChatMessage

    var body: some View {
        if message.role == .notice {
            Text(message.text)
                .font(.system(size: 12))
                .foregroundStyle(AgentStyle.muted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        } else {
            HStack(alignment: .top, spacing: 10) {
                if message.role == .user { Spacer(minLength: AgentStyle.messageGutter) }
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
                .frame(maxWidth: AgentStyle.messageMaxWidth, alignment: .leading)
                .padding(.horizontal, 15)
                .padding(.vertical, 11)
                .foregroundStyle(.white)
                .tint(.white)
                .background(message.role == .user ? AgentStyle.userSurface : AgentStyle.assistantSurface,
                            in: RoundedRectangle(cornerRadius: AgentStyle.bubbleRadius, style: .continuous))
                if message.role == .assistant { Spacer(minLength: AgentStyle.messageGutter) }
            }
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
