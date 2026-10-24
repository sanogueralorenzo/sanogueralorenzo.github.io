import AppKit

/// The windows an agent opens once the person agrees: a normal window, a
/// Blank Window or a Quick Window over an allowed, unlocked Space, and a
/// Private Window, which no tool reaches into afterwards. Crest asks each
/// time unless the person let the connection open windows until it
/// disconnects. An agent never loads an address into private browsing the
/// person already has open.
extension BrowserMacAgents {
    // MARK: - Types

    private struct PrivateOpening: Decodable {
        let url: String?
    }

    private struct PrivateReceipt: Encodable {
        let windowID: UUID
    }

    private struct WindowOpening: Decodable {
        let space: UUID?
        let url: String?
    }

    private struct WindowReceipt: Encodable {
        let windowID: UUID
        let spaceID: UUID
        let tabID: UUID?
    }

    // MARK: - Actions - Windows

    /// Opens a Private Window, at `url` when given. With one already open,
    /// it only comes forward, and an address is refused before anything
    /// changes.
    func openPrivateWindow(_ call: BrowserAgentCall) async throws(BrowserAgentFailure) -> AgentToolResult {
        _ = try reach(call)
        let opening = try call.arguments(PrivateOpening.self)
        let url = try opening.url.map(Self.address)
        try refuseAddressInOpenPrivateBrowsing(url)
        try await approveWindow(.privateWindow, over: nil, at: url, call)
        // The person may have opened private browsing while asked.
        try refuseAddressInOpenPrivateBrowsing(url)
        windows.openPrivateWindow()
        if let url, application.privateBrowser.openNewTab(url: url) == nil {
            throw .refused("Crest could not open the private address.")
        }
        note(.openedPrivateWindow, url?.absoluteString ?? "", call)
        return .data(PrivateReceipt(windowID: application.privatePages.windowID))
    }

    func openWindow(_ call: BrowserAgentCall) async throws(BrowserAgentFailure) -> AgentToolResult {
        let opening = try call.arguments(WindowOpening.self)
        let url = try opening.url.map(Self.address)
        try await approveWindow(.window, over: try resolveSpace(opening.space, call), at: url, call)
        let space = try resolveSpace(opening.space, call)
        let window = try openWindow(over: space)
        var tabID: UUID?
        if let url {
            guard let opened = window.browser.openNewTab(url: url, in: space.id, selecting: true) else {
                throw .refused("Crest could not open the address in this Space.")
            }
            _ = try claim(opened, call)
            tabID = opened
        }
        bringForward(window)
        note(.openedWindow, url?.absoluteString ?? "", call)
        return .data(WindowReceipt(windowID: window.id, spaceID: space.id, tabID: tabID))
    }

    func openBlankWindow(_ call: BrowserAgentCall) async throws(BrowserAgentFailure) -> AgentToolResult {
        let opening = try call.arguments(WindowOpening.self)
        guard opening.url == nil else { throw .invalidArguments("a Blank Window does not take a URL.") }
        try await approveWindow(.blankWindow, over: try resolveSpace(opening.space, call), at: nil, call)
        let space = try resolveSpace(opening.space, call)
        let assignment = BrowserSpaceRuntimeAssignment(spaceID: space.id, profileID: space.profileID)
        let request = BrowserMacWindowRequest.temporary(sourceWindowID: nil, assignment: assignment)
        windows.open(request, activation: .key)
        guard let window = application.windowCoordinator.existingModel(for: request.id) else { throw .noWindow }
        bringForward(window)
        note(.openedWindow, "", call)
        return .data(WindowReceipt(windowID: window.id, spaceID: space.id, tabID: nil))
    }

    func openQuickWindow(_ call: BrowserAgentCall) async throws(BrowserAgentFailure) -> AgentToolResult {
        let opening = try call.arguments(WindowOpening.self)
        guard let text = opening.url else { throw .invalidArguments("url is missing.") }
        let url = try Self.address(text)
        try await approveWindow(.quickWindow, over: try resolveSpace(opening.space, call), at: url, call)
        let space = try resolveSpace(opening.space, call)
        let assignment = BrowserSpaceRuntimeAssignment(spaceID: space.id, profileID: space.profileID)
        let request = BrowserQuickWindowRequest(url: url, spaceAssignment: assignment)
        // The same address in the same Space brings its Quick Window forward.
        guard let windowID = windows.openQuickWindow(request), windows.quickWindow(windowID) != nil else {
            throw .noWindow
        }
        note(.openedWindow, url.absoluteString, call)
        return .data(WindowReceipt(windowID: windowID, spaceID: space.id, tabID: nil))
    }

    /// Asks the person whether the agent behind `call` may open a window of
    /// `kind`, over `space` at `address` where it gives them, unless they let
    /// its connection open windows until it disconnects. Throws
    /// `windowDeclined` when they don't.
    func approveWindow(
        _ kind: BrowserAgentWindowKind, over space: SpaceModel?, at address: URL?, _ call: BrowserAgentCall
    ) async throws(BrowserAgentFailure) {
        let session = try connectedSession(call)
        guard !session.opensWindows || kind.asksEachTime else { return }
        let spaceName = try space.flatMap { space throws(BrowserAgentFailure) in
            try reach(call).spaces.first { $0.spaceID == space.id }?.name
        }
        let opening = BrowserAgentWindowOpening(
            agentName: try allowedName(of: session), kind: kind, spaceName: spaceName,
            address: address?.absoluteString)
        let answer = try await approvals.approve(opening, for: ObjectIdentifier(call.link))
        if answer.lasts { _ = try? core.send(AllowAgentWindows(sessionID: call.sessionID)) }
    }

    /// Refuses an address while the person has private browsing open, which
    /// an agent never loads one into.
    private func refuseAddressInOpenPrivateBrowsing(_ address: URL?) throws(BrowserAgentFailure) {
        guard address != nil, windows.isOpen(.private) else { return }
        throw .refused(
            "A Private Window is already open. Crest opens an address only in a new Private Window; ask the person to close theirs first."
        )
    }

    /// Opening a window happens only for explicit window and show-tab commands.
    func openWindow(over space: SpaceModel) throws(BrowserAgentFailure) -> BrowserMacWindowModel {
        let request = BrowserMacWindowRequest.normal(sourceWindowID: nil)
        windows.open(request, activation: .key)
        guard let window = application.windowCoordinator.existingModel(for: request.id) else { throw .noWindow }
        window.browser.selectSpace(space.id)
        return window
    }
}
