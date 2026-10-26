import AppKit
import SwiftUI

/// Whether agents the person runs on this Mac, such as coding agents, may use
/// Crest; how to connect one; which of the person's Spaces agents reach;
/// whether agents may run scripts in pages; and the agents connected now and
/// allowed before.
struct BrowserAgentsSettingsPane: View {
    // MARK: - Types

    /// An agent Crest knows how to connect, with the line that adds Crest to
    /// it.
    private struct Setup: Identifiable {
        let name: LocalizedStringKey
        let line: (String) -> String

        var id: String { line("") }

        static var all: [Self] {
            [
                Self(name: "Claude Code") { "claude mcp add --transport stdio crest -- \"\($0)\" mcp" },
                Self(name: "Codex") { "codex mcp add crest -- \"\($0)\" mcp" },
                Self(name: "Other agents") {
                    #"{ "mcpServers": { "crest": { "command": "\#($0)", "args": ["mcp"] } } }"#
                },
            ]
        }
    }

    // MARK: - Static Variables

    /// How much of each connected agent's activity shows, the latest, and how
    /// its rows sit under the agent's.
    static let shownActivity = 5
    static let activitySymbolWidth: CGFloat = 18
    static let activityIndent: CGFloat = 24

    // MARK: - Variables

    let core: CrestCore
    @Environment(BrowserAgentEndpointStatus.self) private var endpoint: BrowserAgentEndpointStatus?
    @State private var failure: String?

    private var preferences: AgentPreferences { core.state.agentPreferences }
    /// The helper agents run, inside this app.
    private let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/crest-browser").path
    /// Whether macOS runs this copy of Crest from a temporary place, where the
    /// helper's path changes every launch.
    private var isTranslocated: Bool { helper.contains("/AppTranslocation/") }

    /// The Spaces of the person's own session that are not being deleted,
    /// which are the only ones agents may be allowed to reach.
    private var spaces: [SpaceModel] {
        guard let workspace = core.state.workspaces.values.first(where: { $0.kind.keepsAppPreferences }) else {
            return []
        }
        let deleting = Set(workspace.spaceDeletions.map(\.spaceID))
        return workspace.spaces.models.filter { !deleting.contains($0.id) }
    }

    // MARK: - Actions - Presentation

    var body: some View {
        BrowserSettingsPane(.agents) {
            Section {
                Toggle("Allow agents to use Crest", isOn: isOn)
                    .accessibilityIdentifier("agents-enabled")
            } footer: {
                CrestFormFootnote(
                    "Coding agents on this Mac can read and act on tabs and history in the Spaces you choose, and open windows. Crest asks before each new agent connects."
                )
            }
            if preferences.isOn { connection }
            Section {
                ForEach(spaces) { space in
                    Toggle(isOn: allows(space)) {
                        BrowserSpaceIdentityLabel(space: space)
                    }
                }
            } header: {
                Text("Spaces")
            } footer: {
                CrestFormFootnote(
                    "Agents can open a private window but never reach into one, and see only the name of a locked Space."
                )
            }
            .disabled(!preferences.isOn)
            Section {
                Toggle("Let agents run scripts in pages", isOn: runsScripts)
            } footer: {
                CrestFormFootnote("Scripts run with the page’s own access to the site.")
            }
            .disabled(!preferences.isOn)
            if !core.state.agentSessions.isEmpty {
                Section {
                    ForEach(core.state.agentSessions, id: \.sessionID) { session in
                        BrowserAgentRow(name: session.name, detail: nil, color: session.color ?? .agentDefault) {
                            Button("Disconnect") { send(EndAgentSession(sessionID: session.sessionID)) }
                        }
                        ForEach(
                            Array(session.activity.suffix(Self.shownActivity).reversed().enumerated()), id: \.offset
                        ) {
                            _, activity in
                            BrowserAgentActivityRow(activity: activity)
                        }
                    }
                    Button("Stop All Agents") { send(StopAllAgents()) }
                } header: {
                    Text("Connected")
                } footer: {
                    CrestFormFootnote(
                        "Stopping every agent disconnects it and keeps it out of the tabs it used until Crest quits.")
                }
            }
            Section {
                if preferences.agents.isEmpty {
                    Text("No agents yet").foregroundStyle(.secondary)
                }
                ForEach(Array(preferences.agents.enumerated()), id: \.offset) { _, agent in
                    BrowserAgentRow(name: agent.name, detail: Self.detail(of: agent.identity), color: nil) {
                        Button("Forget") { send(ForgetAgent(identity: agent.identity)) }
                    }
                }
            } header: {
                Text("Allowed agents")
            } footer: {
                CrestFormFootnote("Forgetting an agent disconnects it. Crest asks again the next time it connects.")
            }
            if let failure { Text(failure).foregroundStyle(.red) }
        }
    }

    /// How to connect an agent, while agents are on: a line for each agent
    /// Crest knows, or why agents can't reach Crest.
    @ViewBuilder private var connection: some View {
        Section {
            if isTranslocated {
                Text("Move Crest to your Applications folder to connect agents.").foregroundStyle(.secondary)
            } else if case .failed(let failure) = endpoint?.state {
                Text(failure.message).foregroundStyle(.red)
            } else {
                ForEach(Setup.all) { setup in
                    LabeledContent(setup.name) {
                        Button("Copy Setup") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(setup.line(helper), forType: .string)
                        }
                    }
                }
            }
        } header: {
            Text("Connect an Agent")
        } footer: {
            CrestFormFootnote(
                "Paste the setup in your agent’s terminal or settings. Crest must be open while the agent works.")
        }
    }

    /// The program that vouches for an allowed agent: where it is, or its
    /// signing identifier. An interpreter's agent is named for itself, so the
    /// interpreter shows here.
    private static func detail(of identity: AgentIdentity) -> String? {
        identity.path ?? identity.signingID
    }

    // MARK: - Actions - Preferences

    private var isOn: Binding<Bool> {
        Binding {
            preferences.isOn
        } set: {
            send(SetAgents(isOn: $0))
        }
    }

    private var runsScripts: Binding<Bool> {
        Binding {
            preferences.runsScripts
        } set: {
            send(SetAgentScripts(runsScripts: $0))
        }
    }

    private func allows(_ space: SpaceModel) -> Binding<Bool> {
        Binding {
            preferences.spaceIDs.contains(space.id)
        } set: {
            send(AllowAgentSpace(spaceID: space.id, allowed: $0))
        }
    }

    private func send(_ intent: some AgentIntent) {
        do {
            try core.send(intent)
            failure = nil
        } catch { failure = error.explanation }
    }
}

/// An agent: its name, what tells it apart, the colour it wears while
/// connected, and what the person can do about it.
/// One thing a connected agent did, newest first under its row: what, what
/// about, and when.
private struct BrowserAgentActivityRow: View {
    let activity: AgentActivity

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: activity.kind.symbol)
                .foregroundStyle(.secondary)
                .frame(width: BrowserAgentsSettingsPane.activitySymbolWidth)
                .accessibilityHidden(true)
            VStack(alignment: .leading) {
                Text(activity.kind.title)
                if !activity.subject.isEmpty {
                    Text(verbatim: activity.subject)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
            Text(activity.at, format: .dateTime.hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.leading, BrowserAgentsSettingsPane.activityIndent)
        .accessibilityElement(children: .combine)
    }
}

private struct BrowserAgentRow<Action: View>: View {
    let name: String
    let detail: String?
    let color: BrandColor?
    @ViewBuilder let action: () -> Action

    var body: some View {
        HStack {
            if let color {
                Image(systemName: "sparkles")
                    .foregroundStyle(color.color)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading) {
                Text(name)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
            action()
        }
    }
}

#if DEBUG
    #Preview("Agent rows") {
        Form {
            BrowserAgentRow(name: "Claude", detail: nil, color: BrandColor(red: 0.85, green: 0.47, blue: 0.34)) {
                Button("Disconnect") {}
            }
            BrowserAgentRow(name: "claude", detail: "com.anthropic.claude-code", color: nil) { Button("Forget") {} }
        }
        .formStyle(.grouped)
        .frame(width: 520)
    }
#endif
