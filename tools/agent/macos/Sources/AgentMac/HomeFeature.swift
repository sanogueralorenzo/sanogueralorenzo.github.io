import SwiftUI

struct HomeFeatureView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    welcomeCard
                    workspaceCard
                    recentTasks
                }
                .frame(maxWidth: 600, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 22)
                .padding(.top, 24)
                .padding(.bottom, 20)
            }
            .scrollPosition(id: $model.homeScrollPosition, anchor: .bottom)
            if let error = model.connectionError {
                ConnectionError(message: error) { Task { await model.start() } }
            }
            MessageComposer(model: model)
            bottomBar
        }
    }

    private var header: some View {
        HStack {
            Color.clear.frame(width: 76, height: 30)
            Spacer()
            HStack(spacing: 8) {
                Image(systemName: "sparkle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AgentStyle.clay)
                    .frame(width: 25, height: 25)
                    .background(AgentStyle.surface, in: Circle())
                Text("Agent")
                    .font(.system(size: 15, weight: .semibold))
            }
            Spacer()
            Button {
                Task { await model.newConversation() }
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AgentStyle.graphite)
                    .frame(width: 34, height: 30)
                    .background(AgentStyle.surface, in: Capsule())
            }
            .buttonStyle(.plain)
            .help("New session")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(AgentStyle.line).frame(height: 1) }
    }

    private var welcomeCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 9) {
                Image(systemName: "sparkle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AgentStyle.clay)
                Text("Your coordination space")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AgentStyle.graphite)
            }
            Text("What can I help you get moving?")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(AgentStyle.graphite)
            Text("Send a task to the right specialist, then follow the work here.")
                .font(.system(size: 14))
                .lineSpacing(3)
                .foregroundStyle(AgentStyle.muted)
            VStack(alignment: .leading, spacing: 9) {
                tip("Delegate a focused task")
                tip("Get concise progress updates")
                tip("Open a session to continue the conversation")
            }
            .padding(.top, 2)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AgentStyle.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var workspaceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Your workspace")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AgentStyle.graphite)
            workspaceRow(
                symbol: "point.3.connected.trianglepath.dotted",
                title: "Agent runtime",
                detail: model.isConnected ? "Ready for tasks" : "Connecting…",
                isReady: model.isConnected
            )
            Rectangle().fill(AgentStyle.line).frame(height: 1)
            workspaceRow(
                symbol: "terminal",
                title: "Codex",
                detail: codexStatus,
                isReady: model.setupStatus?.codex.connected == true
            )
        }
        .padding(18)
        .background(AgentStyle.inputSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AgentStyle.line) }
    }

    private var codexStatus: String {
        guard let status = model.setupStatus else { return "Checking connection…" }
        if status.codex.connected { return "Connected" }
        return status.codex.installed ? "Available" : "Not installed"
    }

    private var recentTasks: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent tasks")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                if !model.homeEntries.isEmpty {
                    Text("\(model.homeEntries.count)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AgentStyle.muted)
                }
            }
            .foregroundStyle(AgentStyle.graphite)

            if model.homeEntries.isEmpty {
                Text("Your dispatched tasks will show up here.")
                    .font(.system(size: 13))
                    .foregroundStyle(AgentStyle.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(AgentStyle.inputSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(model.homeEntries) { entry in
                        HomeEntryView(entry: entry) {
                            if let sessionId = entry.sessionId { Task { await model.selectSession(sessionId) } }
                        }
                        .id(entry.id)
                    }
                }
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            Button {} label: {
                bottomItem("house.fill", title: "Home", selected: true)
            }
            .buttonStyle(.plain)
            .disabled(true)

            Menu {
                if model.sessions.isEmpty {
                    Text("No sessions yet")
                } else {
                    ForEach(model.sessions) { session in
                        Button(session.title ?? "Untitled session") {
                            Task { await model.selectSession(session.id) }
                        }
                    }
                }
            } label: {
                bottomItem("clock", title: "Sessions", selected: false)
            }
            .menuStyle(.borderlessButton)
            .help("Open a recent session")

        }
        .frame(maxWidth: 380)
        .frame(maxWidth: .infinity)
        .padding(.top, 9)
        .padding(.bottom, 7)
        .overlay(alignment: .top) { Rectangle().fill(AgentStyle.line).frame(height: 1) }
    }

    private func tip(_ title: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Circle().fill(AgentStyle.clay).frame(width: 5, height: 5)
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(AgentStyle.graphite)
        }
    }

    private func workspaceRow(symbol: String, title: String, detail: String, isReady: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AgentStyle.muted)
                .frame(width: 32, height: 32)
                .background(AgentStyle.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(AgentStyle.graphite)
                Text(detail).font(.system(size: 11)).foregroundStyle(AgentStyle.muted)
            }
            Spacer()
            Image(systemName: isReady ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 15))
                .foregroundStyle(isReady ? AgentStyle.clay : AgentStyle.muted.opacity(0.6))
        }
        .accessibilityElement(children: .combine)
    }

    private func bottomItem(_ symbol: String, title: String, selected: Bool) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 15, weight: selected ? .semibold : .regular))
            Text(title).font(.system(size: 10, weight: selected ? .medium : .regular))
        }
        .foregroundStyle(selected ? AgentStyle.clay : AgentStyle.muted)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}
