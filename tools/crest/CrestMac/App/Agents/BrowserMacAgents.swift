import AppKit
import os

/// Lets agents the person runs, such as coding agents, use Crest while the
/// person allows it in Settings. An agent runs the `crest-browser` helper
/// this Crest ships, which speaks the Model Context Protocol with the agent
/// and reaches Crest through a Unix domain socket that exists only while
/// agents are on, and that only this Crest's own helper may use.
///
/// The first time an agent calls a tool, the person is asked whether it may
/// use Crest, and the core keeps the answer, keyed by the agent's code
/// signature. From then on the agent reaches only the Spaces of the person's
/// own session that they allowed, as the core's `AgentReach` answers; every
/// tab it touches shows its badge, and the person can stop it in any tab.
/// Turning agents off, or forgetting an agent, ends its connections.
@MainActor
final class BrowserMacAgents {
    // MARK: - Static Variables

    static let maximumConnections = 32

    private static let logger = Logger(subsystem: "com.pauldavis.crest", category: "Agents")

    // MARK: - Types

    /// One helper's connection: the agent behind it, as macOS vouches for it
    /// and as it names itself, and the core session it holds once the person
    /// allowed it.
    final class Link {
        let connection: BrowserAgentConnection
        var client: AgentClientInfo?
        var isAttached = false
        /// The agent's connection in the core, once the person allowed it.
        var sessionID: UUID?
        /// The session being begun while the person is asked, which calls
        /// that arrive meanwhile share.
        var beginning: Task<Result<UUID, BrowserAgentFailure>, Never>?
        /// The engine page of each tab that renders for the agent, and of each
        /// that keeps its activity, by tab. A later call asks again only when
        /// the tab's page changed, as when it moved to another engine.
        var heldPages: [UUID: UUID] = [:]
        var observedPages: [UUID: UUID] = [:]
        /// When the agent last gave each tab input, which may start a load a
        /// moment later.
        var lastInput: [UUID: ContinuousClock.Instant] = [:]

        init(connection: BrowserAgentConnection) {
            self.connection = connection
        }

        /// The agent program, as it vouches for the agent it runs.
        var agent: BrowserAgentPeer.Program? { connection.peer.agent?.running(client) }
    }

    // MARK: - Variables

    unowned let application: BrowserMacApplication
    unowned let windows: BrowserMacWindows
    /// Where agents' helpers connect, or nil when this launch offers none.
    let path: String?
    /// What a helper must be to be heard: this Crest's own.
    private let helper: BrowserAgentHelperRequirement?
    private var listener: BrowserAgentListener?
    private var links: [ObjectIdentifier: Link] = [:]
    /// The person's answers to agents connecting and deleting history.
    let approvals: BrowserAgentApprovals
    /// The work running on each tab, which the next call on that tab waits
    /// for, so calls on one tab never interleave.
    private var tabWork: [UUID: Task<Void, Never>] = [:]
    private var stopped = false

    var core: CrestCore { application.browser.core }

    // MARK: - Initializers

    init(
        application: BrowserMacApplication, windows: BrowserMacWindows,
        approvals: BrowserAgentApprovals = BrowserAgentApprovals()
    ) {
        self.application = application
        self.windows = windows
        self.approvals = approvals
        helper = BrowserAgentHelperRequirement(bundle: .main)
        path = helper == nil ? nil : Bundle.main.bundleIdentifier.flatMap(AgentSocketLocation.path(forApp:))
    }

    // MARK: - Actions - Lifecycle

    /// Follows the person's agent preferences from now on: the socket exists
    /// while agents are on.
    func start() {
        follow()
    }

    /// Removes the socket and ends every connection for good, as the app
    /// quits.
    func stop() {
        stopped = true
        closeEndpoint()
    }

    private func follow() {
        guard !stopped else { return }
        withObservationTracking {
            apply(core.state.agentPreferences, connected: core.state.agentSessions)
        } onChange: { [weak self] in
            Task { @MainActor in self?.follow() }
        }
    }

    /// Opens or removes the socket as agents are turned on or off, ends the
    /// connections of an agent the core no longer keeps connected, as when
    /// the person forgot it, and lets go of the pages of tabs an agent may no
    /// longer use, as one the person stopped it in.
    private func apply(_ preferences: AgentPreferences, connected: [AgentSessionState]) {
        guard preferences.isOn else {
            closeEndpoint()
            return
        }
        openEndpoint()
        let sessions = Dictionary(connected.map { ($0.sessionID, $0) }, uniquingKeysWith: { first, _ in first })
        for link in links.values {
            guard let sessionID = link.sessionID else { continue }
            guard let session = sessions[sessionID] else {
                end(link)
                continue
            }
            let used = Set(session.tabIDs)
            for tabID in Set(link.heldPages.keys).union(link.observedPages.keys) where !used.contains(tabID) {
                letGo(tabID, of: link)
            }
        }
    }

    private func openEndpoint() {
        guard listener == nil else { return }
        let status = application.agentEndpoint
        guard let path, let helper else {
            status.state = .failed(.unavailable)
            return
        }
        let listener = BrowserAgentListener(path: path, helper: helper) { [weak self] connection in
            // The main queue keeps connections and their lines in the order
            // they arrived.
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.admit(connection) } }
        }
        do {
            try listener.start()
            self.listener = listener
            status.state = .listening
        } catch {
            Self.logger.error("The agent socket could not open: \(String(describing: error), privacy: .public)")
            status.state = .failed(error)
        }
    }

    private func closeEndpoint() {
        if let listener, !listener.stop() {
            Self.logger.error("The agent socket did not close in time.")
        }
        listener = nil
        application.agentEndpoint.state = .closed
        for link in links.values { end(link) }
        approvals.dismissAll()
    }

    // MARK: - Actions - Questions

    /// The agent connected as `call`'s session.
    func connectedSession(_ call: BrowserAgentCall) throws(BrowserAgentFailure) -> AgentSessionState {
        guard let session = core.state.agentSessions.first(where: { $0.sessionID == call.sessionID }) else {
            throw .rejected(.unknownAgentSession(UnknownAgentSession(sessionID: call.sessionID)))
        }
        return session
    }

    /// The name the person allowed `session`'s agent under, which every
    /// question about it names, never the one it introduced itself by.
    func allowedName(of session: AgentSessionState) throws(BrowserAgentFailure) -> String {
        guard let agent = core.state.agentPreferences.agents.first(where: { $0.identity == session.identity }) else {
            throw .rejected(.unknownAgentSession(UnknownAgentSession(sessionID: session.sessionID)))
        }
        return agent.name
    }

    // MARK: - Actions - Activity

    /// Keeps that the agent behind `call` did `kind` about `subject`, which
    /// Settings › Agents lists under it while it stays connected.
    func note(_ kind: AgentActivityKind, _ subject: String, _ call: BrowserAgentCall) {
        _ = try? core.send(NoteAgentActivity(sessionID: call.sessionID, kind: kind, subject: subject))
    }

    // MARK: - Actions - Connections

    private func admit(_ connection: BrowserAgentConnection) {
        guard listener != nil, links.count < Self.maximumConnections else {
            connection.close()
            return
        }
        let link = Link(connection: connection)
        let key = ObjectIdentifier(link)
        links[key] = link
        connection.open { [weak self] line in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.receive(line, on: key) } }
        } ended: { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.forget(key) } }
        }
    }

    /// The helper hung up: the agent is no longer connected.
    private func forget(_ key: ObjectIdentifier) {
        guard let link = links.removeValue(forKey: key) else { return }
        release(link)
    }

    private func end(_ link: Link) {
        link.connection.close()
        links[ObjectIdentifier(link)] = nil
        release(link)
    }

    /// Lets go of what `link`'s agent held: its pages render and keep
    /// activity for it no more, and the core disconnects it.
    private func release(_ link: Link) {
        approvals.withdraw(ObjectIdentifier(link))
        for tabID in Set(link.heldPages.keys).union(link.observedPages.keys) { letGo(tabID, of: link) }
        guard let sessionID = link.sessionID else { return }
        link.sessionID = nil
        let name = core.state.agentSessions.first { $0.sessionID == sessionID }?.name ?? link.agent?.agentName
        _ = try? core.send(EndAgentSession(sessionID: sessionID))
        if let name {
            BrowserNoticeCenter.shared.post(
                BrowserNotice(message: String(localized: "\(name) stopped using Crest"), systemImage: "sparkles"))
        }
    }

    /// Lets `link` go of tab `tabID`'s page: it renders and keeps activity
    /// for agents no more once no other connection uses it, since the engine
    /// keeps one of each per page.
    private func letGo(_ tabID: UUID, of link: Link) {
        let page = agentPage(tabID)?.enginePage
        let others = links.values.filter { $0 !== link }
        if let held = link.heldPages.removeValue(forKey: tabID), page?.id == held,
            !others.contains(where: { $0.heldPages[tabID] == held })
        {
            page?.holdRendering(false, size: .zero)
        }
        if let observed = link.observedPages.removeValue(forKey: tabID), page?.id == observed,
            !others.contains(where: { $0.observedPages[tabID] == observed })
        {
            page?.observeActivity(false)
        }
        link.lastInput[tabID] = nil
    }

    // MARK: - Actions - Requests

    private func receive(_ line: Data, on key: ObjectIdentifier) {
        guard let link = links[key] else { return }
        guard let request = try? JSONDecoder().decode(AgentLinkRequest.self, from: line) else {
            end(link)
            return
        }
        request.handle(on: self, from: link)
    }

    /// The helper behind `link` introduced the agent `client`, speaking link
    /// `version`.
    func attach(_ link: Link, version: Int, client: AgentClientInfo?) {
        guard version == AgentLinkRequest.version else {
            reply(.refused(reason: .staleHelper), on: link)
            link.connection.close()
            return
        }
        guard core.state.agentPreferences.isOn else {
            reply(.refused(reason: .agentsOff), on: link)
            return
        }
        link.client = client
        link.isAttached = true
        reply(.attached(tools: AgentToolDefinition.catalog), on: link)
    }

    /// The agent behind `link` called tool `name` with `arguments`, as call
    /// `id`, which is answered once the tool finishes.
    func call(_ id: Int, name: String, arguments: AgentJSON, from link: Link) {
        let key = ObjectIdentifier(link)
        Task { [weak self] in
            guard let self else { return }
            let result = await perform(name, arguments: arguments, on: link)
            guard links[key] != nil else { return }
            reply(.result(id: id, result: result), on: link)
        }
    }

    private func reply(_ response: AgentLinkResponse, on link: Link) {
        guard var line = try? JSONEncoder().encode(response) else { return }
        // An answer longer than the helper reads would end the agent's whole
        // connection, so that one call fails instead.
        if line.count > AgentLinkResponse.maximumBytes, case .result(let id, _) = response,
            let refusal = try? JSONEncoder().encode(
                AgentLinkResponse.result(id: id, result: .error(BrowserAgentFailure.tooLarge.message)))
        {
            line = refusal
        }
        link.connection.send(line)
    }

    /// Answers the agent's call of tool `name`, once the person allowed the
    /// agent.
    private func perform(_ name: String, arguments: AgentJSON, on link: Link) async -> AgentToolResult {
        guard link.isAttached else { return .error(BrowserAgentFailure.notAttached.message) }
        do throws(BrowserAgentFailure) {
            let sessionID = try await session(for: link)
            guard let tool = BrowserAgentTool.named(name) else { throw .unknownTool(name) }
            return try await tool.perform(
                BrowserAgentCall(agents: self, link: link, sessionID: sessionID, arguments: arguments))
        } catch {
            return .error(error.message)
        }
    }

    /// The agent's connection in the core: begun now when the person already
    /// allowed it, or after they allow it when it is new. Calls that arrive
    /// while it begins share it, as an agent's first calls often come
    /// together.
    private func session(for link: Link) async throws(BrowserAgentFailure) -> UUID {
        if let sessionID = link.sessionID { return sessionID }
        if let beginning = link.beginning { return try await beginning.value.get() }
        let beginning = Task { await self.begin(link) }
        link.beginning = beginning
        let begun = await beginning.value
        link.beginning = nil
        return try begun.get()
    }

    private func begin(_ link: Link) async -> Result<UUID, BrowserAgentFailure> {
        do throws(BrowserAgentFailure) {
            return .success(try await beginSession(for: link))
        } catch {
            return .failure(error)
        }
    }

    private func beginSession(for link: Link) async throws(BrowserAgentFailure) -> UUID {
        guard core.state.agentPreferences.isOn else { throw .rejected(.agentsOff(AgentsOff())) }
        guard let agent = link.agent else { throw .unidentified }
        let sessionID = UUID()
        do {
            _ = try core.send(BeginAgentSession(sessionID: sessionID, identity: agent.identity, name: agent.agentName))
        } catch .agentNotApproved {
            try await approvals.approve(agent, client: link.client, for: ObjectIdentifier(link))
            guard links[ObjectIdentifier(link)] != nil, core.state.agentPreferences.isOn else { throw .declined }
            do {
                _ = try core.send(ApproveAgent(agent: ApprovedAgent(identity: agent.identity, name: agent.agentName)))
                _ = try core.send(
                    BeginAgentSession(sessionID: sessionID, identity: agent.identity, name: agent.agentName))
            } catch {
                throw .rejected(error)
            }
        } catch {
            throw .rejected(error)
        }
        link.sessionID = sessionID
        BrowserNoticeCenter.shared.post(
            BrowserNotice(message: String(localized: "\(agent.agentName) is using Crest"), systemImage: "sparkles"))
        return sessionID
    }

    // MARK: - Actions - Tabs

    /// Runs `work` on tab `tabID` once the work an agent started on it before
    /// has finished, so calls on one tab never interleave.
    func serially(
        on tabID: UUID, _ work: @escaping @MainActor () async throws(BrowserAgentFailure) -> AgentToolResult
    ) async throws(BrowserAgentFailure) -> AgentToolResult {
        let earlier = tabWork[tabID]
        let result = Task { @MainActor () async -> Result<AgentToolResult, BrowserAgentFailure> in
            await earlier?.value
            do throws(BrowserAgentFailure) {
                return .success(try await work())
            } catch {
                return .failure(error)
            }
        }
        tabWork[tabID] = Task { _ = await result.value }
        return try await result.value.get()
    }

    /// The live page of tab `tabID` when it has one, which an agent holds.
    func agentPage(_ tabID: UUID) -> BrowserPage? {
        application.pages.residentPage(ofTab: tabID)
    }
}
