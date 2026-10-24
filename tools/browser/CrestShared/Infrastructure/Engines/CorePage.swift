import Foundation
import OSLog

/// A page the core opened for this platform. Its identity is made here and
/// never depends on the engine. Giving it a new owner, loading an address in
/// it or releasing it goes through the core; a page is released once, and the
/// core then asks its engine to close what it holds. Its live state is the
/// core's, read from `CoreState`.
@MainActor
final class CorePage {
    // MARK: - Static Variables

    private static let logger = Logger(subsystem: "com.pauldavis.crest", category: "Pages")

    /// Times each step through a page's history, from the person's input to
    /// the command the core hands its engine, for Instruments.
    static let historySignposter = OSSignposter(subsystem: "com.pauldavis.crest", category: "PageHistory")

    // MARK: - Variables

    let id: UUID
    private weak var core: CrestCore?
    private(set) var isReleased = false
    /// The owner kept what it needs to bring the page back when it released it.
    private var keptState = false
    /// Runs when the core moved the page to another engine, so its owner
    /// hosts it there; `movedHost(from:)` answers what it hosts. Set by the
    /// page's owner.
    var engineMoved: (@MainActor () -> Void)?

    /// The core's model of the page, until the page is gone.
    var state: PageStateModel? { core?.state.pages[id] }

    /// What the page shows now as the core holds it: its engine's latest
    /// report and why its latest navigation failed. Blank until the core
    /// holds the page.
    var live: PageLiveState { state?.live ?? .blank }

    /// The registered engines this page can move to: every one but its own.
    /// Empty before the core holds the page or while one engine is registered.
    var otherEngines: [EngineKind] {
        guard let current = state?.engine, let engines else { return [] }
        return engines.engines.map(\.kind).filter { $0 != current }
    }

    // MARK: - Initializers

    init(id: UUID = UUID(), core: CrestCore) {
        self.id = id
        self.core = core
    }

    // MARK: - Actions - Engines

    /// What the platform hosts for the page now that the core moved it off
    /// engine `current`; nil when it did not move.
    func movedHost(from current: EngineKind) -> (any EngineHostedPage)? {
        core?.engines.movedHost(for: self, from: current)
    }

    // MARK: - Actions - Data

    /// Erases the site at `host` from every engine's store for profile
    /// `profileID`, the page's, and answers whether each engine erased all of it.
    func eraseSiteData(host: String, profileID: UUID) async -> Bool {
        guard let core else { return false }
        return await core.deleteData(
            DeleteSiteData(requestID: UUID(), profileID: profileID, ephemeral: false, host: host))
    }

    // MARK: - Actions - Ownership

    /// Gives the page to `tabID` in a Space of `workspaceID`, or to a transient
    /// request when `tabID` is nil, hosted by `windowID`. False when a rule
    /// refuses it, such as a window that already hosts a page for the tab or a
    /// Space with another profile.
    func move(to workspaceID: UUID, spaceID: UUID, tabID: UUID?, windowID: UUID) -> Bool {
        guard !isReleased, let core else { return false }
        do {
            try core.send(
                MovePage(
                    pageID: id, workspaceID: workspaceID, spaceID: spaceID, tabID: tabID,
                    windowID: windowID))
            return true
        } catch {
            Self.logger.debug(
                "The core kept page \(self.id, privacy: .public) where it was: \(String(describing: error))")
            return false
        }
    }

    /// Tells the core the page is gone. `keepingState` says its owner kept what
    /// it needs to bring the page back. A page unloaded that way may be
    /// released again for good, so the core forgets what it showed; any other
    /// call after the first changes nothing.
    func release(keepingState: Bool) {
        guard !isReleased || (keptState && !keepingState) else { return }
        let isFirst = !isReleased
        isReleased = true
        keptState = keepingState
        _ = try? core?.send(ReleasePage(pageID: id, keepsState: keepingState))
        if isFirst { core?.engines.forget(id) }
    }

    /// The core unloaded the page under memory pressure and already asked its
    /// engine to close it, keeping what brings it back; the page is released
    /// without telling the core again.
    func unloaded() {
        guard !isReleased else { return }
        isReleased = true
        core?.engines.forget(id)
    }

    // MARK: - Actions - Navigation

    /// Asks the core to load what the person typed or chose, an address or
    /// words to search for, which the core resolves by the rules of the
    /// page's Space and engine. False when a rule refuses it, such as a locked
    /// Space or input that names nothing a page can load.
    @discardableResult
    func navigate(to input: String) -> Bool {
        guard !isReleased, let core else { return false }
        do {
            try core.send(Navigate(pageID: id, input: input))
            return true
        } catch {
            Self.logger.debug(
                "The core loaded nothing in page \(self.id, privacy: .public): \(String(describing: error))")
            return false
        }
    }

    /// Asks the core to load `url`, an address Crest already holds such as
    /// the tab's stored location, as it is rather than as typed words. False
    /// when a rule refuses it.
    @discardableResult
    func load(_ url: URL) -> Bool {
        guard !isReleased, let core else { return false }
        do {
            try core.send(LoadAddress(pageID: id, url: url.absoluteString))
            return true
        } catch {
            Self.logger.debug(
                "The core loaded nothing in page \(self.id, privacy: .public): \(String(describing: error))")
            return false
        }
    }

    /// This device's link preferences, as the core last published them.
    var linkPreferences: LinkPreferences? { core?.state.linkPreferences }

    /// Whether a window the page opened with `gesture`, which its engine
    /// accepted, comes to the front. A core that cannot answer brings it
    /// forward, as an ordinary new-window request does.
    func selectsOpenedWindow(gesture: LinkGesture) -> Bool {
        (try? core?.query(OpenedWindowSelection(gesture: gesture)))?.selects ?? true
    }

    /// Tells the core no page will load a link the page's engine staged, so
    /// the engine forgets it. A link its engine keeps itself needs nothing.
    func discardStagedLink(_ link: BrowserEngineNavigation) {
        guard link.sourcePageID == id, let stagedLinkID = UUID(uuidString: link.token) else { return }
        _ = try? core?.send(DiscardStagedLink(sourcePageID: id, stagedLinkID: stagedLinkID))
    }

    /// Sends the person's answer to a question the core asked about the page.
    /// An answer to a question that no longer waits changes nothing.
    func answer(_ intent: some PromptIntent) {
        _ = try? core?.send(intent)
    }

    /// The entries the page can go back and forward to, nearest first, as the
    /// core keeps its history. Empty before the core holds the page.
    var history: PageHistoryList {
        (try? core?.query(PageHistoryEntries(pageID: id))) ?? PageHistoryList(back: [], forward: [])
    }

    /// The page's back and forward history as its tab's archive keeps it
    /// across a relaunch, opaque here; nil for none.
    var archivedHistory: Data? {
        (try? core?.query(ArchivedPageHistory(pageID: id)))?.archive
    }

    /// Moves the page `offset` entries through its history: back when
    /// negative. Going back from a failed navigation leaves the failure first.
    func stepHistory(by offset: Int) {
        guard !isReleased, offset != 0, let core else { return }
        let interval = Self.historySignposter.beginInterval("Step History")
        defer { Self.historySignposter.endInterval("Step History", interval) }
        _ = try? core.send(StepHistory(pageID: id, offset: offset))
    }

    /// Moves the page to the history entry `entryID` names, as a menu offered it.
    func showHistoryEntry(_ entryID: UUID) {
        guard !isReleased, let core else { return }
        let interval = Self.historySignposter.beginInterval("Show History Entry")
        defer { Self.historySignposter.endInterval("Show History Entry", interval) }
        _ = try? core.send(ShowHistoryEntry(pageID: id, entryID: entryID))
    }

    /// Leaves the page's failed navigation for the document behind it.
    func leaveFailure() {
        guard !isReleased, live.failure != nil else { return }
        _ = try? core?.send(LeavePageFailure(pageID: id))
    }

    // MARK: - Actions - Engines

    /// The engines this device registered, as the core last published them,
    /// or nil before one registered.
    var engines: EngineRoster? { core?.state.engines }

    /// Opens `origin`'s pages on `engine` from now on, as a choice made in
    /// `spaceID`, and moves this page there, which loads what it showed.
    /// False when a rule refuses either, such as a locked Space.
    @discardableResult
    func open(_ origin: SiteOrigin, in spaceID: UUID, on engine: EngineKind) -> Bool {
        guard !isReleased, let core else { return false }
        return core.open(origin, in: spaceID, on: engine, moving: id)
    }

    /// Moves this page alone to `engine`, which loads what it showed; the
    /// site's other pages keep opening where they did. False when a rule
    /// refuses it, such as a locked Space or an engine this device did not
    /// register.
    @discardableResult
    func move(to engine: EngineKind) -> Bool {
        guard !isReleased, let core else { return false }
        do {
            try core.send(RehostPage(pageID: id, engine: engine, remembersSite: false))
            return true
        } catch {
            Self.logger.debug(
                "The core kept page \(self.id, privacy: .public) on its engine: \(String(describing: error))")
            return false
        }
    }

    // MARK: - Actions - Reports

    /// Reports what the page's engine saw it do, through that engine. `icon`
    /// is the image a `PageIconChanged` names. A released page reports nothing.
    func report(_ event: some EngineEvent, icon: Data? = nil) {
        guard !isReleased else { return }
        core?.engines.report(event, for: id, icon: icon)
    }
}
