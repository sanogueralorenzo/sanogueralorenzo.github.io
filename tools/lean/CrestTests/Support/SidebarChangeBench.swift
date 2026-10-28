import Foundation

@testable import Crest

/// A window's sidebar inputs over the first Space of a session on a
/// memory-only core, a second window over the same workspace, and pages for
/// the Space's current tabs, so each change reaches the read model through
/// the core as a real one does.
@MainActor
final class SidebarChangeBench {
    // MARK: - Variables

    let core: CrestCore
    let store: BrowserStore
    let other: BrowserStore
    let workspace: WorkspaceModel
    let space: SpaceModel
    let window: WindowStateModel
    /// The Space's current tabs outside splits, and a page showing each of
    /// the first ones at its address.
    let currentTabs: [TabStateModel]
    let pages: [CorePage]
    /// A page that belongs to no tab, whose visits reach only history.
    let visitPage: CorePage
    /// The session as the core opened it.
    let opening: WorkspaceOpened
    /// Pages a preparation opened for new tabs on a Start Page.
    var startPages: [CorePage] = []
    /// The kinds of change the batches since the last `clearChanges()` brought.
    private(set) var changeKinds: Set<String> = []

    // MARK: - Initializers

    init(session: SessionState.Seed, pageCount: Int = 100) {
        let core = CrestCore.hostingPages()
        var opened: WorkspaceOpened?
        core.batchApplied = { changes in
            for case .workspaceOpened(let change) in changes { opened = change }
        }
        let store = BrowserStore(seed: session, core: core)
        guard let opening = opened, let workspace = core.state.workspaces[store.window.workspaceID],
            let space = workspace.spaces.model(session.spaces[0].id)
        else { preconditionFailure("The bench's session did not open.") }
        self.core = core
        self.store = store
        self.opening = opening
        self.workspace = workspace
        self.space = space
        other = store.makeWindowStore()
        store.selectPresentedSpace(space.id)
        guard let window = core.state.windows[store.windowID] else {
            preconditionFailure("The bench's window is not open.")
        }
        self.window = window
        currentTabs = space.tabs.models.filter { $0.placement == .current && $0.splitGroupID == nil }
        pages = currentTabs.prefix(pageCount).map { tab in
            guard let page = store.openReportingPage(for: tab.id, in: space.id),
                let address = tab.url.flatMap(URL.init(string:))
            else { preconditionFailure("The bench could not open a page for a tab.") }
            store.finishNavigation(of: page, to: address, titled: tab.title)
            return page
        }
        guard let visitPage = store.openReportingPage(for: nil, in: space.id) else {
            preconditionFailure("The bench could not open a page for visits.")
        }
        self.visitPage = visitPage
        core.batchApplied = { [weak self] changes in
            guard let self else { return }
            changeKinds.formUnion(changes.map { change in Mirror(reflecting: change).children.first?.label ?? "?" })
        }
    }

    // MARK: - Actions - Reports

    func clearChanges() {
        changeKinds = []
    }

    /// Reports what a page's engine would see: `title`, its loading state,
    /// and otherwise what the page shows now.
    func report(_ page: CorePage, title: String? = nil, isLoading: Bool? = nil, drains: Bool = true) {
        let live = page.live
        page.report(
            PageStateChanged(
                pageID: page.id,
                snapshot: PageSnapshot(
                    url: live.url, pendingURL: nil, title: title ?? live.title,
                    isLoading: isLoading ?? live.isLoading,
                    security: live.security, media: live.media)))
        if drains { core.drain() }
    }

    /// Reports that a page found a new image for the address it shows.
    func showIcon(on page: CorePage, run: Int) {
        page.report(
            PageIconChanged(pageID: page.id, url: page.live.url ?? "", accent: nil),
            icon: Data([UInt8(truncatingIfNeeded: run), 0x51, 0x72]))
        core.drain()
    }
}
