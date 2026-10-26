import AppKit

/// What an agent may do with itself, the Spaces it reaches and their tabs.
/// Each call reads the core's `AgentReach` or claims its tab first, so a Space
/// the person stopped allowing or locked, or a tab they stopped the agent
/// using, is out of reach at once. Tabs open, close and come forward through
/// the window stores Crest's own commands use, so the core's rules and a
/// page's leave-page check apply as they do for the person. An agent
/// creates a window only for an explicit command from the person.
extension BrowserMacAgents {
    // MARK: - Types

    private struct Introduction: Decodable {
        let name: String?
        let color: String?
    }

    private struct SpaceQuery: Decodable {
        let space: UUID?
    }

    private struct Opening: Decodable {
        let space: UUID
        let url: String
        let show: Bool?
    }

    private struct Navigation: Decodable {
        let tab: UUID
        let url: String?
        let action: BrowserAgentNavigationAction?
    }

    struct TabReference: Decodable {
        let tab: UUID
    }

    private struct SpaceListing: Encodable {
        let id: UUID
        let name: String
        let locked: Bool
        let active: Bool?
        let symbol: String?
        let icon: String?
    }

    private struct TabListing: Encodable {
        let id: UUID
        let space: UUID
        let title: String
        let url: String?
        let placement: String
        let isPinned: Bool
        let isSaved: Bool
        let folders: [String]
        let inUse: Bool
        let shown: Bool
    }

    // MARK: - Actions - Identity

    func identify(_ call: BrowserAgentCall) async throws(BrowserAgentFailure) -> AgentToolResult {
        let introduction = try call.arguments(Introduction.self)
        let color = introduction.color.flatMap(Self.brandColor)
        do {
            _ = try core.send(IdentifyAgent(sessionID: call.sessionID, name: introduction.name, color: color))
        } catch {
            throw .rejected(error)
        }
        let shown = core.state.agentSessions.first { $0.sessionID == call.sessionID }?.name ?? introduction.name ?? ""
        let note = introduction.color != nil && color == nil ? " Crest couldn’t read the colour; use #RRGGBB." : ""
        return .message("Crest shows you to the person as \(shown).\(note)")
    }

    /// `text` as an opaque brand colour: #RRGGBB or #RGB.
    private static func brandColor(_ text: String) -> BrandColor? {
        var digits = text.trimmingCharacters(in: .whitespaces)
        if digits.hasPrefix("#") { digits.removeFirst() }
        if digits.count == 3 { digits = digits.map { "\($0)\($0)" }.joined() }
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        return BrandColor(
            red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255, alpha: 1)
    }

    // MARK: - Actions - Spaces

    func listSpaces(_ call: BrowserAgentCall) throws(BrowserAgentFailure) -> AgentToolResult {
        let reach = try reach(call)
        let workspace = reach.workspaceID.flatMap { core.state.workspaces[$0] }
        let selected = application.stackedWindowIDs.compactMap {
            application.windowCoordinator.existingModel(for: $0)
        }.first { !$0.isTemporary }?.browser.selectedSpaceID
        let spaces = reach.spaces.map { reached in
            let space = reached.isLocked ? nil : workspace?.spaces.model(reached.spaceID)
            return SpaceListing(
                id: reached.spaceID, name: reached.name, locked: reached.isLocked,
                active: space.map { $0.id == selected }, symbol: space?.settings.symbol,
                icon: space.flatMap(spaceIcon))
        }
        return .data(["spaces": spaces])
    }

    // MARK: - Actions - Tabs

    func listTabs(_ call: BrowserAgentCall) throws(BrowserAgentFailure) -> AgentToolResult {
        let query = try call.arguments(SpaceQuery.self)
        let reach = try reach(call)
        var spaces = reach.spaces
        if let id = query.space {
            guard let space = spaces.first(where: { $0.spaceID == id }) else {
                throw .rejected(.agentSpaceUnavailable(AgentSpaceUnavailable(spaceID: id)))
            }
            spaces = [space]
        }
        let workspace = reach.workspaceID.flatMap { core.state.workspaces[$0] }
        let tabs = spaces.flatMap { space in
            space.tabs.map { describe($0, in: space.spaceID, model: workspace?.spaces.model(space.spaceID)) }
        }
        let locked = spaces.filter(\.isLocked).map(\.name)
        let note =
            locked.isEmpty
            ? nil : "Locked Spaces show no tabs until the person unlocks them: \(locked.joined(separator: ", "))."
        return .data(["tabs": tabs], note: note)
    }

    func openTab(_ call: BrowserAgentCall) async throws(BrowserAgentFailure) -> AgentToolResult {
        let opening = try call.arguments(Opening.self)
        let url = try Self.address(opening.url)
        let reach = try reach(call)
        guard let reached = reach.spaces.first(where: { $0.spaceID == opening.space }),
            let workspaceID = reach.workspaceID,
            let space = core.state.workspaces[workspaceID]?.spaces.model(opening.space)
        else { throw .rejected(.agentSpaceUnavailable(AgentSpaceUnavailable(spaceID: opening.space))) }
        guard !reached.isLocked else { throw .spaceLocked(reached.name) }
        let window = frontWindow(over: space)
        let shows = opening.show == true && window != nil
        let browser = window?.browser ?? application.browser
        guard let tabID = browser.openNewTab(url: url, in: space.id, selecting: shows) else {
            throw .refused("Crest could not open a tab in this Space.")
        }
        _ = try claim(tabID, call)
        note(.openedTab, url.absoluteString, call)
        // Its page loads now, behind if need be, so the tab shows its site
        // while the agent works.
        _ = try? page(for: tabID, call)
        if shows, let window { bringForward(window) }
        let note = opening.show == true && window == nil ? "No Crest window is open, so the tab opened behind." : nil
        return .data(["tab": try listing(tabID, call)], note: note)
    }

    func navigate(_ call: BrowserAgentCall) async throws(BrowserAgentFailure) -> AgentToolResult {
        let navigation = try call.arguments(Navigation.self)
        let url = try navigation.url.map(Self.address)
        guard url != nil || navigation.action != nil else { throw .invalidArguments("give url or action.") }
        return try await serially(on: navigation.tab) { () async throws(BrowserAgentFailure) -> AgentToolResult in
            let page = try self.page(for: navigation.tab, call)
            if let url {
                page.corePage.load(url)
                self.note(.loadedPage, url.absoluteString, call)
            } else {
                navigation.action?.perform(on: page.corePage, page.enginePage)
            }
            return .data(["tab": try self.listing(navigation.tab, call)])
        }
    }

    func showTab(_ call: BrowserAgentCall) async throws(BrowserAgentFailure) -> AgentToolResult {
        let reference = try call.arguments(TabReference.self)
        let (space, tab) = try claim(reference.tab, call)
        let window: BrowserMacWindowModel
        if let existing = frontWindow(over: space) {
            window = existing
        } else {
            try await approveWindow(.window, over: space, at: nil, call)
            window = try openWindow(over: space)
        }
        window.browser.selectSpace(space.id)
        guard window.browser.activateSessionTab(tab.id, in: space.id) else {
            throw .refused("Crest could not show the tab.")
        }
        bringForward(window)
        return .data(["tab": try listing(tab.id, call)])
    }

    func closeTab(_ call: BrowserAgentCall) async throws(BrowserAgentFailure) -> AgentToolResult {
        let reference = try call.arguments(TabReference.self)
        let (space, tab) = try claim(reference.tab, call)
        guard tab.placement == .current else { throw .pinnedOrSaved }
        let title = (try? listing(tab.id, call))?.title ?? ""
        let browser = frontWindow(over: space)?.browser ?? application.browser
        if browser.closeTab(tab.id, in: space.id) {
            note(.closedTab, title, call)
            return .data(["closed": true])
        }
        // A page asked to answer whether it may go answers after this returns.
        let deadline = ContinuousClock.now + .seconds(2)
        while space.tabs.contains(tab.id), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
        let closed = !space.tabs.contains(tab.id)
        if closed { note(.closedTab, title, call) }
        return .data(
            ["closed": closed],
            note: closed ? nil : "The page asked the person whether to leave; the tab is still open.")
    }

    // MARK: - Actions - Reach

    /// What the agent reaches now, as the core answers.
    func reach(_ call: BrowserAgentCall) throws(BrowserAgentFailure) -> AgentReachList {
        let reach: AgentReachList
        do {
            reach = try core.query(AgentReach(sessionID: call.sessionID))
        } catch {
            throw .rejected(error)
        }
        guard reach.workspaceID != nil else { throw .rejected(.agentsOff(AgentsOff())) }
        return reach
    }

    /// Tab `tabID` and its Space, which the agent uses from now on, as the
    /// core allows.
    func claim(_ tabID: UUID, _ call: BrowserAgentCall) throws(BrowserAgentFailure) -> (SpaceModel, TabStateModel) {
        do {
            _ = try core.send(ClaimAgentTab(sessionID: call.sessionID, tabID: tabID))
        } catch {
            throw .rejected(error)
        }
        for workspace in core.state.workspaces.values where workspace.kind.keepsAppPreferences {
            for space in workspace.spaces.models {
                if let tab = space.tabs.model(tabID) { return (space, tab) }
            }
        }
        throw .rejected(.agentTabUnavailable(AgentTabUnavailable(tabID: tabID)))
    }

    /// `text` as an address an agent may open: http or https, with a host.
    static func address(_ text: String) throws(BrowserAgentFailure) -> URL {
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
            url.host() != nil
        else { throw .unsupportedAddress }
        return url
    }

    private func listing(_ tabID: UUID, _ call: BrowserAgentCall) throws(BrowserAgentFailure) -> TabListing {
        let reach = try reach(call)
        let workspace = reach.workspaceID.flatMap { core.state.workspaces[$0] }
        for space in reach.spaces {
            if let tab = space.tabs.first(where: { $0.tabID == tabID }) {
                return describe(tab, in: space.spaceID, model: workspace?.spaces.model(space.spaceID))
            }
        }
        throw .rejected(.agentTabUnavailable(AgentTabUnavailable(tabID: tabID)))
    }

    private func describe(_ tab: AgentTab, in spaceID: UUID, model: SpaceModel?) -> TabListing {
        let folders = model.flatMap { space in space.tabs.model(tab.tabID).map { folderPath($0, in: space) } } ?? []
        return TabListing(
            id: tab.tabID, space: spaceID, title: tab.title, url: tab.url,
            placement: tab.placement.name, isPinned: tab.placement == .pinned, isSaved: tab.placement == .saved,
            folders: folders, inUse: tab.claimed,
            shown: isShown(tab.tabID))
    }

    private func folderPath(_ tab: TabStateModel, in space: SpaceModel) -> [String] {
        var path: [String] = []
        var visited = Set<UUID>()
        var current = tab.folderID
        while let id = current, visited.insert(id).inserted, let folder = space.folders.model(id) {
            path.insert(folder.title, at: 0)
            current = folder.parentID
        }
        return path
    }

    private func spaceIcon(_ space: SpaceModel) -> String? {
        guard let image = BrowserSpaceSymbolArtworkRenderer.shared.menuImage(for: BrowserSpaceIdentity(space: space)),
            let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
            let png = bitmap.representation(using: .png, properties: [:])
        else { return nil }
        return "data:image/png;base64," + png.base64EncodedString()
    }

    // MARK: - Actions - Windows

    /// Whether a window on screen shows the tab now.
    private func isShown(_ tabID: UUID) -> Bool {
        application.stackedWindowIDs.contains { core.state.windows[$0]?.shownTabIDs.contains(tabID) == true }
    }

    /// The front window over `space`'s workspace, or nil with none open.
    func frontWindow(over space: SpaceModel) -> BrowserMacWindowModel? {
        normalWindows(over: space).first
    }

    /// Includes open models whose native views have not attached yet, after windows AppKit can already stack.
    private func normalWindows(over space: SpaceModel) -> [BrowserMacWindowModel] {
        let stacked = application.stackedWindowIDs
        let pending = application.windowCoordinator.openWindowPages.map(\.windowID).filter { !stacked.contains($0) }
        return (stacked + pending).compactMap { application.windowCoordinator.existingModel(for: $0) }
            .filter { !$0.isTemporary && $0.browser.spaceModel(space.id) != nil }
    }

    /// Shows what `window` selected and brings it forward, and Crest with it.
    func bringForward(_ window: BrowserMacWindowModel) {
        window.pages.select()
        windows.open(window.request, activation: .key)
        NSApp.activate(ignoringOtherApps: true)
    }
}
