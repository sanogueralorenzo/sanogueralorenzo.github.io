import SwiftUI

@main
struct A1RApp: App {
    @StateObject private var model = AppModel()

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
    @ObservedObject var model: AppModel

    var body: some View {
        switch model.state {
        case .starting:
            ProgressView("Starting A1R…")
        case .needsOpenAI:
            SetupView(model: model)
        case .ready:
            ConversationView(model: model)
        case let .failed(message):
            ContentUnavailableView("A1R needs attention", systemImage: "exclamationmark.circle", description: Text(message))
                .safeAreaInset(edge: .bottom) {
                    Button("Try Again") { Task { await model.start() } }.padding()
                }
        }
    }
}

struct SetupView: View {
    @ObservedObject var model: AppModel
    @State private var key = ""

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "wind").font(.system(size: 48)).foregroundStyle(.tint)
            Text("Welcome to A1R").font(.largeTitle.weight(.semibold))
            Text("Connect an OpenAI API key once. It is validated by your local runtime and stored in macOS Keychain.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 440)
            SecureField("OpenAI API key", text: $key).textFieldStyle(.roundedBorder).frame(maxWidth: 420)
            HStack {
                Link("Create an API key", destination: URL(string: "https://platform.openai.com/api-keys")!)
                Spacer()
                Button("Connect") { Task { await model.connectOpenAI(key) } }
                    .buttonStyle(.borderedProminent).disabled(!key.hasPrefix("sk-"))
            }.frame(maxWidth: 420)
        }.padding(40)
    }
}

struct ConversationView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("A1R", systemImage: "wind").font(.headline)
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
                TextField("Message A1R", text: $model.input, axis: .vertical)
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
            Text(message.text.isEmpty ? "…" : message.text)
                .textSelection(.enabled)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(message.role == .user ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
            if message.role == .assistant { Spacer(minLength: 80) }
        }
    }
}
