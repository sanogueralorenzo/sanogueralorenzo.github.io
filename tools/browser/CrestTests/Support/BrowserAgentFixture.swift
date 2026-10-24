import AppKit
import Darwin
import XCTest

@testable import Crest

/// Runs public native tool dispatch with an isolated, approved agent session.
@MainActor
final class BrowserAgentFixture {
    // MARK: - Types

    /// Answers for the person: allows every agent, lets it delete history
    /// while `deletesHistory` and open windows as `windows` says, keeping
    /// each deletion and window it was asked about.
    final class Answers: BrowserAgentAsking {
        // MARK: - Variables

        var deletesHistory = true
        var windows = BrowserAgentAnswer.once
        private(set) var deletions: [BrowserAgentHistoryDeletion] = []
        private(set) var openings: [BrowserAgentWindowOpening] = []

        // MARK: - Actions - Questions

        func approveAgent(
            _ agent: BrowserAgentPeer.Program, client: AgentClientInfo?, dismissal: BrowserPromptDismissal?
        ) async -> Bool {
            true
        }

        func approveHistoryDeletion(_ deletion: BrowserAgentHistoryDeletion, dismissal: BrowserPromptDismissal?)
            async -> Bool
        {
            deletions.append(deletion)
            return deletesHistory
        }

        func approveWindow(_ opening: BrowserAgentWindowOpening, dismissal: BrowserPromptDismissal?) async
            -> BrowserAgentAnswer
        {
            openings.append(opening)
            return windows
        }
    }

    // MARK: - Variables

    let host = WebKitShellHost()
    let answers = Answers()
    let application: BrowserMacApplication
    let windows: BrowserMacWindows
    let agents: BrowserMacAgents
    let link: BrowserMacAgents.Link
    let sessionID = UUID()
    let space: SpaceModel
    var core: CrestCore { application.browser.core }

    // MARK: - Initializers

    init() throws {
        application = try BrowserMacApplication()
        windows = BrowserMacWindows(application: application, engineHost: host)
        agents = BrowserMacAgents(
            application: application, windows: windows, approvals: BrowserAgentApprovals(asking: answers))
        space = try XCTUnwrap(application.browser.shownSpace)
        let identity = AgentIdentity(teamID: nil, signingID: nil, path: "/private/tmp/crest-test-agent", client: nil)
        var descriptors: [Int32] = [0, 0]
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0 else { throw POSIXError(.EIO) }
        Darwin.close(descriptors[1])
        let peer = BrowserAgentPeer(helperProcessID: getpid(), agent: nil)
        link = BrowserMacAgents.Link(connection: BrowserAgentConnection(descriptor: descriptors[0], peer: peer))
        try core.send(SetAgents(isOn: true))
        try core.send(AllowAgentSpace(spaceID: space.id, allowed: true))
        try core.send(ApproveAgent(agent: ApprovedAgent(identity: identity, name: "Test")))
        try core.send(BeginAgentSession(sessionID: sessionID, identity: identity, name: "Test"))
    }

    // MARK: - Actions - Tools

    func invoke(_ name: String, _ arguments: [String: AgentJSON] = [:]) async throws -> AgentJSON {
        let tool = try XCTUnwrap(BrowserAgentTool.named(name))
        let answer = try await tool.perform(
            BrowserAgentCall(agents: agents, link: link, sessionID: sessionID, arguments: .object(arguments)))
        if answer.isError { throw BrowserAgentFailure(answer.content.first?.text ?? "The tool failed.") }
        let text = try XCTUnwrap(answer.content.first?.text)
        return try JSONDecoder().decode(AgentJSON.self, from: Data(text.utf8))
    }

    /// What tool `name` answers `arguments` with, as the agent's model reads
    /// it.
    func message(_ name: String, _ arguments: [String: AgentJSON] = [:]) async throws -> String {
        let tool = try XCTUnwrap(BrowserAgentTool.named(name))
        let answer = try await tool.perform(
            BrowserAgentCall(agents: agents, link: link, sessionID: sessionID, arguments: .object(arguments)))
        let text = try XCTUnwrap(answer.content.first?.text)
        if answer.isError { throw BrowserAgentFailure(text) }
        return text
    }

    /// The page of tab `tabID`, which the agent uses.
    func page(for tabID: UUID) throws -> BrowserPage {
        try agents.page(
            for: tabID, BrowserAgentCall(agents: agents, link: link, sessionID: sessionID, arguments: .object([:])))
    }

    /// Fails the test unless tool `name` refuses `arguments`.
    func assertRefused(
        _ name: String, _ arguments: [String: AgentJSON] = [:], file: StaticString = #filePath, line: UInt = #line
    ) async {
        do {
            _ = try await invoke(name, arguments)
            XCTFail("\(name) should refuse \(arguments).", file: file, line: line)
        } catch {}
    }
}
