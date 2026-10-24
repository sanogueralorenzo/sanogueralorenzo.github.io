import AppKit

/// Opens what another app hands Crest, a web link or a document, where the
/// core places it, for either engine's product. The core names the window
/// and the Space: the frontmost window over the person's own Spaces, never a
/// private or torn-off tab's window, or with none open, one to open, or for a
/// link, a Quick Window alone, whether or not any window is open. Unlocking a
/// Space that asks for it stays here, since it asks the person.
@MainActor
final class BrowserMacExternalOpening {
    // MARK: - Types

    /// Where a link from another app lands, once its Space is open to this
    /// process.
    struct LinkDestination {
        let placement: ExternalLinkPlacement
        let assignment: BrowserSpaceRuntimeAssignment

        /// The window a Quick Window for the link promotes into: the open
        /// window the core named, or none when no window is open.
        var quickWindowTarget: UUID? { placement.opensWindow ? nil : placement.windowID }
    }

    // MARK: - Variables

    private unowned let application: BrowserMacApplication
    private unowned let windows: BrowserMacWindows

    // MARK: - Initializers

    init(application: BrowserMacApplication, windows: BrowserMacWindows) {
        self.application = application
        self.windows = windows
    }

    // MARK: - Actions - Opening

    /// Opens `urls`: the documents together, then each link in turn.
    func open(_ urls: [URL]) async {
        let documents = urls.filter(\.isFileURL)
        if !documents.isEmpty { await openDocuments(documents) }
        for url in urls where !url.isFileURL { await openLink(url) }
    }

    /// Opens a link from another app where the core routes it: in a Quick
    /// Window, or as a new tab in the window it names. Answers whether it
    /// opened.
    @discardableResult
    func openLink(_ url: URL) async -> Bool {
        guard let destination = await destination(for: url) else { return false }
        if destination.placement.opensQuickWindow {
            windows.openQuickWindow(
                BrowserQuickWindowRequest(
                    url: url, spaceAssignment: destination.assignment, targetWindowID: destination.quickWindowTarget))
            return true
        }
        guard
            let request = preparedWindow(destination.placement.windowID, opens: destination.placement.opensWindow),
            application.openExternalLink(url, in: destination.assignment, window: request.id)
        else { return false }
        present(request)
        return true
    }

    /// Opens documents another app handed Crest as tabs in the Space the core
    /// names, which is the one on screen, unlocking it first when it asks.
    func openDocuments(_ urls: [URL]) async {
        let browser = application.browser
        guard
            let placement = try? browser.core.query(RouteLocalDocument(windowIDs: application.stackedWindowIDs)),
            let spaceID = placement.spaceID, let space = browser.spaceModel(spaceID)
        else { return }
        let assignment = BrowserSpaceRuntimeAssignment(space: space)
        guard await application.spaceAccess.unlock(space),
            let request = preparedWindow(placement.windowID, opens: placement.opensWindow),
            let model = application.windowCoordinator.existingModel(for: request.id),
            model.browser.spaceModel(matching: assignment) != nil
        else { return }
        BrowserCommandActions(
            browser: model.browser, pages: model.pages, chrome: model.chrome, windows: windows,
            spaceAccess: application.spaceAccess, targetWindowID: model.id
        ).openLocalDocuments(urls, in: assignment)
        present(request)
    }

    /// Where a link from another app lands, or nil when it lands nowhere. The
    /// core never routes one to a locked Space, so the unlock only confirms
    /// the Space is still open to this process.
    func destination(for url: URL) async -> LinkDestination? {
        let browser = application.browser
        guard
            let placement = try? browser.core.query(
                RouteExternalLink(windowIDs: application.stackedWindowIDs, url: url.absoluteString)),
            let spaceID = placement.spaceID, let space = browser.spaceModel(spaceID)
        else { return nil }
        let assignment = BrowserSpaceRuntimeAssignment(space: space)
        guard await application.spaceAccess.unlock(space), browser.spaceModel(matching: assignment) != nil else {
            return nil
        }
        return LinkDestination(placement: placement, assignment: assignment)
    }

    // MARK: - Actions - Windows

    /// The request for the window an open lands in, whose model exists before
    /// the window shows: `windowID` while it is open, or with `opens`, the
    /// saved window to open under it. Nil when there is none.
    private func preparedWindow(_ windowID: UUID?, opens: Bool) -> BrowserMacWindowRequest? {
        guard let windowID else { return nil }
        let request = BrowserMacWindowRequest.reopening(windowID)
        let model =
            opens
            ? application.windowCoordinator.model(for: request)
            : application.windowCoordinator.existingModel(for: windowID)
        return model == nil ? nil : request
    }

    /// Brings the window `request` names forward, opening it when it is not
    /// open, and the app with it.
    private func present(_ request: BrowserMacWindowRequest) {
        windows.open(request, activation: .key)
        NSApp.activate(ignoringOtherApps: true)
    }
}
