import Foundation

extension BrowserMacAgents {
    // MARK: - Types

    private struct SearchQuery: Decodable {
        let space: UUID?
    }

    private struct SearchCatalog: Encodable {
        struct Provider: Encodable {
            let id: String
            let name: String
            let shortcuts: [String]
            let url: String
        }
        let providers: [Provider]
        let defaultProvider: Provider?
    }

    private struct HistoryQuery: Decodable {
        let query: String?
        let limit: Int?
        let domain: String?
    }

    private struct HistoryDeletion: Decodable {
        let space: UUID
        let url: String
    }

    private struct HistoryDeletionReceipt: Encodable {
        let space: UUID
        let removed: Int
    }

    private struct HistoryList: Encodable {
        struct Entry: Encodable {
            let id: UUID
            let space: UUID
            let spaceName: String
            let url: String
            let title: String
            let lastVisitedAt: String
            let lastVisitTime: Double
        }
        let entries: [Entry]
    }

    // MARK: - Actions - Search

    func listSearchProviders(_ call: BrowserAgentCall) throws(BrowserAgentFailure) -> AgentToolResult {
        let query = try call.arguments(SearchQuery.self)
        let space = try resolveSpace(query.space, call)
        let catalog = BrowserSearchCatalog(core: core)
        func describe(_ provider: SearchProvider) -> SearchCatalog.Provider {
            .init(id: provider.name, name: provider.title, shortcuts: provider.shortcuts, url: provider.searchTemplate)
        }
        return .data(
            SearchCatalog(
                providers: catalog.providers.filter { catalog.isEnabled($0) }.map(describe),
                defaultProvider: catalog.provider(for: space.settings.browsingPreferences, isPrivate: false).map(
                    describe)))
    }

    // MARK: - Actions - History

    /// Reads live core history, filtering before the global cap; engine disk flushes are irrelevant.
    func searchHistory(_ call: BrowserAgentCall) throws(BrowserAgentFailure) -> AgentToolResult {
        let query = try call.arguments(HistoryQuery.self)
        let limit = query.limit ?? 25
        guard (1...1000).contains(limit) else { throw .invalidArguments("limit must be between 1 and 1000.") }
        let reach = try reach(call)
        guard let workspaceID = reach.workspaceID, let workspace = core.state.workspaces[workspaceID] else {
            throw .rejected(.agentsOff(AgentsOff()))
        }
        let terms = (query.query ?? "").lowercased().split(whereSeparator: { $0.isWhitespace })
        let domain = query.domain?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let entries = reach.spaces.filter { !$0.isLocked }.flatMap { reached -> [HistoryList.Entry] in
            guard let space = workspace.spaces.model(reached.spaceID) else { return [] }
            return space.history.entries.compactMap { entry in
                let text = (entry.url + " " + entry.title).lowercased()
                guard terms.allSatisfy({ text.contains($0) }) else { return nil }
                // Browser and extension pages are outside the agent's reach, even if persisted as history.
                guard let url = URL(string: entry.url), let scheme = url.scheme?.lowercased(),
                    scheme == "http" || scheme == "https", let host = url.host?.lowercased()
                else { return nil }
                if let domain, !domain.isEmpty {
                    guard host == domain || host.hasSuffix("." + domain) else { return nil }
                }
                return .init(
                    id: entry.id, space: space.id, spaceName: reached.name, url: entry.url,
                    title: entry.title,
                    lastVisitedAt: entry.lastVisitedAt.ISO8601Format(.init(includingFractionalSeconds: true)),
                    lastVisitTime: entry.lastVisitedAt.timeIntervalSince1970 * 1000)
            }
        }
        return .data(
            HistoryList(
                entries: Array(
                    entries.sorted {
                        if $0.lastVisitTime != $1.lastVisitTime { return $0.lastVisitTime > $1.lastVisitTime }
                        return $0.id.uuidString < $1.id.uuidString
                    }.prefix(limit))))
    }

    /// Removes every visit to one address from an allowed, unlocked Space's
    /// history through the core, once the person agrees. History keeps an
    /// address without its fragment, so the comparison drops it, as the core
    /// does. An address the Space has no visit to removes nothing and asks
    /// nothing.
    func deleteHistory(_ call: BrowserAgentCall) async throws(BrowserAgentFailure) -> AgentToolResult {
        let deletion = try call.arguments(HistoryDeletion.self)
        let address = String(try Self.address(deletion.url).absoluteString.prefix { $0 != "#" })
        let space = try resolveSpace(deletion.space, call)
        guard space.history.entries.contains(where: { $0.url == address }) else {
            return .data(HistoryDeletionReceipt(space: space.id, removed: 0))
        }
        let agentName = try allowedName(of: try connectedSession(call))
        let spaceName = try reach(call).spaces.first { $0.spaceID == space.id }?.name ?? ""
        try await approvals.approve(
            BrowserAgentHistoryDeletion(agentName: agentName, address: address, spaceName: spaceName),
            for: ObjectIdentifier(call.link))
        // The person may lock the Space, or stop allowing it, while asked.
        let current = try resolveSpace(deletion.space, call)
        guard let workspaceID = try reach(call).workspaceID else { throw .rejected(.agentsOff(AgentsOff())) }
        let before = current.history.entries.count
        do {
            try core.send(RemoveHistoryAddress(workspaceID: workspaceID, spaceID: current.id, address: address))
        } catch {
            throw .rejected(error)
        }
        let removed = before - current.history.entries.count
        if removed > 0 { note(.deletedHistory, address, call) }
        return .data(HistoryDeletionReceipt(space: current.id, removed: removed))
    }

    // MARK: - Actions - Spaces

    /// Uses only this session's current unlocked reach; locked names never grant a capability.
    func resolveSpace(_ id: UUID?, _ call: BrowserAgentCall) throws(BrowserAgentFailure) -> SpaceModel {
        let reach = try reach(call)
        let activeID = application.stackedWindowIDs.compactMap { application.windowCoordinator.existingModel(for: $0) }
            .first { !$0.isTemporary }?.browser.selectedSpaceID
        let available = reach.spaces.filter { !$0.isLocked }
        let reached =
            id.flatMap { requested in available.first { $0.spaceID == requested } }
            ?? (id == nil ? (available.first { $0.spaceID == activeID } ?? available.first) : nil)
        guard let reached, let workspaceID = reach.workspaceID,
            let space = core.state.workspaces[workspaceID]?.spaces.model(reached.spaceID)
        else { throw .refused("The opening Space is unavailable. Choose an allowed, unlocked Space.") }
        return space
    }
}
