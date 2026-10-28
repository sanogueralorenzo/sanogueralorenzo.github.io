import AppKit

@MainActor
final class BrowserMacExternalOpening {
    // MARK: - Types

    /// Where a link from another app lands, once its Space is open to this
    /// process.
    struct Destination {
        let placement: ExternalOpenPlacement
        let assignment: BrowserSpaceRuntimeAssignment
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

    /// Opens an external link as a tab in the current regular Space.
    @discardableResult
    func openLink(_ url: URL) async -> Bool {
        guard let destination = await destination() else { return false }
        guard
            let request = preparedWindow(destination.placement.windowID, opens: destination.placement.opensWindow),
            application.openExternalLink(url, in: destination.assignment, window: request.id)
        else { return false }
        present(request)
        return true
    }

    func openDocuments(_ urls: [URL]) async {
        guard let destination = await destination(),
            let request = preparedWindow(destination.placement.windowID, opens: destination.placement.opensWindow),
            let model = application.windowCoordinator.existingModel(for: request.id),
            model.browser.spaceModel(matching: destination.assignment) != nil
        else { return }
        BrowserCommandActions(
            browser: model.browser, pages: model.pages, chrome: model.chrome, windows: windows, targetWindowID: model.id
        ).openLocalDocuments(urls, in: destination.assignment)
        present(request)
    }

    func destination() async -> Destination? {
        let browser = application.browser
        guard
            let placement = try? browser.core.query(
                ExternalOpenDestination(windowIDs: application.stackedWindowIDs)),
            let spaceID = placement.spaceID, let space = browser.spaceModel(spaceID)
        else { return nil }
        let assignment = BrowserSpaceRuntimeAssignment(space: space)
        guard browser.spaceModel(matching: assignment) != nil else {
            return nil
        }
        return Destination(placement: placement, assignment: assignment)
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
