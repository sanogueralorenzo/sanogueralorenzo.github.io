import Foundation
import Observation

@Observable
@MainActor
final class BrowserPageHost {
    // MARK: - Types

    // MARK: - Variables

    /// Each tab's resident page.
    @ObservationIgnored var runtimes: [UUID: BrowserTabRuntime] = [:] {
        didSet { residencyChanged() }
    }
    /// The tabs with a resident page, each observed on its own, so a sidebar
    /// row or a card reads only whether its own tab has one. A tab's page and
    /// the window presenting it are observed on its runtime.
    let residentTabIDs = ObservedSet<UUID>()
    /// Moves whenever a tab gains or loses its page, for what reads the
    /// resident pages as a whole.
    var revision = 0
    /// Where tabs' pages leave their engine state on disk when they go, and
    /// when their scene stops being active. The core keeps what brings an
    /// unloaded page back in memory only, so a relaunch restores each tab's
    /// history from here, as does a tab whose state the core no longer holds.
    let tabState: BrowserTabStateCoordinator
    let nativeTabs = BrowserNativeTabStore()
    /// The Spaces whose pages are being let go or whose data is being deleted.
    @ObservationIgnored var spacesReleasingData: Set<UUID> = []
    @ObservationIgnored var spacesDeletingData: Set<UUID> = []
    /// Takes a tab's card off every window that presents it, once its page or
    /// native content went.
    @ObservationIgnored var dropPresentation: @MainActor (UUID) -> Void = { _ in }
    @ObservationIgnored var automaticUnloadTask: Task<Void, Never>?

    // MARK: - Initializers

    /// A host whose tabs leave their state in `archive`, or keep none.
    init(archive: (any BrowserTabStateArchiving)? = nil) {
        tabState = BrowserTabStateCoordinator(archive: archive)
    }

    deinit { automaticUnloadTask?.cancel() }

    // MARK: - Actions - Resident pages

    /// Every tab's resident page.
    var residentPages: [BrowserPlatformPage] { runtimes.values.map(\.page) }

    var livePages: [BrowserPlatformPage] {
        runtimes.values.flatMap(\.allPages)
    }

    // MARK: - Actions - Popup windows

    /// The tab's resident page.
    func page(for tabID: UUID) -> BrowserPlatformPage? {
        runtimes[tabID]?.page
    }

    /// The tab's resident page while it belongs to the Space and profile
    /// `assignment` names.
    func page(matching assignment: BrowserTabRuntimeAssignment) -> BrowserPlatformPage? {
        guard let page = runtimes[assignment.tabID]?.page, page.spaceID == assignment.spaceID,
            page.profileID == assignment.profileID
        else { return nil }
        return page
    }

    /// The tab whose resident page `page` is.
    func tabID(for page: BrowserPlatformPage) -> UUID? {
        runtimes.first { $0.value.page === page }?.key
    }

    /// Keeps `page` as the tab's resident page.
    func retain(_ page: BrowserPlatformPage, for tabID: UUID) {
        if let runtime = runtimes[tabID] {
            runtime.page = page
        } else {
            runtimes[tabID] = BrowserTabRuntime(page: page)
        }
    }

    /// Announces the tabs that gained or lost their page, and moves
    /// `revision` once for readers of the whole set; a change that keeps the
    /// same tabs resident announces nothing.
    private func residencyChanged() {
        let tabIDs = Set(runtimes.keys)
        guard tabIDs != residentTabIDs.members else { return }
        residentTabIDs.replace(with: tabIDs)
        revision &+= 1
    }

    // MARK: - Actions - Reconciliation

    /// Lets go of the pages of tabs that are gone. Their state is not written
    /// out: whether it is worth keeping is settled by the session sweep, which
    /// can tell an archived tab from a deleted one.
    func reconcile(validTabIDs: Set<UUID>) {
        nativeTabs.reconcile(validTabIDs: validTabIDs)
        tabState.retainCopies(for: validTabIDs)
        for tabID in Set(runtimes.keys).subtracting(validTabIDs) {
            evictPage(tabID, preservingTabState: false)
        }
    }

    func reconcile(workspace: WorkspaceModel?, images: FaviconAssets) {
        nativeTabs.reconcile(spaces: workspace?.spaces.models ?? [])
        let reconciliation = BrowserPageReconciliation(
            workspace: workspace, images: images, residentPages: runtimes.lazy.map { ($0.key, $0.value.page) })
        tabState.retainCopies(matching: reconciliation.validAssignments)
        for tabID in reconciliation.tabIDsToArchive {
            archiveTabState(for: tabID)
        }
        releasePages(for: reconciliation.invalidTabIDs, keepingStateOf: reconciliation.tabIDsToArchive)
        for context in reconciliation.navigationContexts {
            context.page.updateNavigationContext(tab: context.tab)
        }
        tabState.prune(keeping: reconciliation.retainedTabIDsByProfileID)
    }

    /// Gives each resident page its tab's current context in `workspace`,
    /// such as the icon `images` keeps for it.
    func reconcileTabIcons(in workspace: WorkspaceModel?, images: FaviconAssets) {
        let tabsByID = Dictionary(
            uniqueKeysWithValues: (workspace?.spaces.models ?? []).flatMap { space in
                space.tabs.models.map { ($0.id, $0) }
            })
        for (tabID, runtime) in runtimes {
            guard let tab = tabsByID[tabID] else { continue }
            runtime.page.updateNavigationContext(tab: BrowserPageTab(tab, images: images))
        }
    }

    /// Gives every page the host keeps the new default zoom.
    func defaultPageZoomDidChange(to zoom: CGFloat) {
        var visited: Set<ObjectIdentifier> = []
        for page in livePages where visited.insert(ObjectIdentifier(page)).inserted {
            page.applyDefaultPageZoom(zoom)
        }
    }

    // MARK: - Actions - Tab state

    /// Writes out the engine state of the resident pages `includes` names.
    /// The app calls this when a scene stops being active, so state survives
    /// a termination before an inactive page is unloaded.
    func archiveResidentTabStates(where includes: (BrowserTabRuntime) -> Bool = { _ in true }) {
        guard tabState.archivesResidentPages else { return }
        for (tabID, runtime) in runtimes where includes(runtime) {
            archiveTabState(for: tabID)
        }
    }

    func flushPendingTabStateWrites() async {
        await tabState.flushPendingWrites()
    }

    /// Keeps the engine state of the tab's resident page. Capture stays on the
    /// main actor; the archive schedules disk writes.
    func archiveTabState(for tabID: UUID) {
        guard let page = runtimes[tabID]?.page else { return }
        tabState.archivePage(page, for: tabID)
    }

    /// The engine state the tab left in its Space and profile, when it still
    /// shows `url`.
    func archivedInteractionState(
        for assignment: BrowserTabRuntimeAssignment, expecting url: URL, consumePendingCopy: Bool = true
    ) -> Data? {
        tabState.interactionState(for: assignment, expecting: url, consumePendingCopy: consumePendingCopy)
    }

    func discardArchivedTabState(matching assignment: BrowserTabRuntimeAssignment) {
        tabState.discardState(matching: assignment)
    }

    // MARK: - Actions - Tab copies

    /// Gives the copy `copyID` of `source`, a tab of the Space `space` names,
    /// the engine state its page keeps for the copy's first page, with its
    /// back and forward history: what the source's resident page shows now,
    /// or the state the source left.
    func prepareTabCopy(from source: TabState, copyID: UUID, in space: BrowserSpaceRuntimeAssignment) {
        let sourceAssignment = BrowserTabRuntimeAssignment(tabID: source.id, in: space)
        let sourceURL = source.url.flatMap(URL.init(string:))
        let url: URL?
        let state: Data?
        let history: Data?
        if let page = page(matching: sourceAssignment) {
            url = page.live.displayURL ?? sourceURL
            state = !page.wasOpenedAsPopup && page.live.documentURL == url ? page.interactionState : nil
            history = page.corePage.archivedHistory
        } else if let sourceURL {
            url = sourceURL
            state = archivedInteractionState(for: sourceAssignment, expecting: sourceURL, consumePendingCopy: false)
            history = tabState.history(for: sourceAssignment, expecting: sourceURL)
        } else {
            url = nil
            state = nil
            history = nil
        }
        tabState.prepareCopy(
            state, url: url, history: history, for: BrowserTabRuntimeAssignment(tabID: copyID, in: space))
    }

    /// Hands the core the back and forward history the tab's pending copy or
    /// archive keeps, before `browser` opens the tab's page, so the page opens
    /// on the engine of the entry it shows and keeps every engine's history.
    func restoreTabHistory(for assignment: BrowserTabRuntimeAssignment, expecting url: URL?, in browser: BrowserStore) {
        guard let url, let history = tabState.history(for: assignment, expecting: url) else { return }
        browser.restoreTabHistory(history, in: assignment.spaceID, for: assignment.tabID)
    }

    /// The address the tab's resident page shows.
    func liveLinkURL(for assignment: BrowserTabRuntimeAssignment) -> URL? {
        page(matching: assignment)?.live.documentURL
    }

    // MARK: - Actions - Unloading

    /// Unloads the tab's page and native content, keeping its engine state
    /// when `preservingTabState`: a tab unloaded by hand comes back where it
    /// was left. Its card goes with it.
    func unloadPage(for tabID: UUID, preservingTabState: Bool = true) {
        if nativeTabs.tabIDs.contains(tabID) {
            nativeTabs.remove(tabID)
            dropPresentation(tabID)
        }
        if preservingTabState { archiveTabState(for: tabID) }
        guard let runtime = runtimes.removeValue(forKey: tabID) else { return }
        runtime.release(keepingState: preservingTabState)
        dropPresentation(tabID)
    }

    /// Unloads the tab's page while it belongs to the Space and profile
    /// `assignment` names; false when it does not.
    @discardableResult
    func unloadPage(for tabID: UUID, matching assignment: BrowserSpaceRuntimeAssignment) -> Bool {
        let tab = BrowserTabRuntimeAssignment(
            tabID: tabID, spaceID: assignment.spaceID, profileID: assignment.profileID)
        if nativeTabs.contains(tab) {
            unloadPage(for: tabID)
            return true
        }
        guard page(matching: tab) != nil else { return false }
        unloadPage(for: tabID)
        return true
    }

    /// Closes the tab's page for good. It differs from an unload only when
    /// the person chose to return to the saved address on the next open,
    /// which drops the state the page left.
    func closeDurablePage(_ assignment: BrowserTabRuntimeAssignment, discardState: Bool) -> Bool {
        guard !nativeTabs.tabIDs.contains(assignment.tabID) || nativeTabs.contains(assignment) else { return false }
        guard
            runtimes[assignment.tabID].map({
                $0.page.spaceID == assignment.spaceID && $0.page.profileID == assignment.profileID
            }) ?? true
        else { return false }
        unloadPage(for: assignment.tabID, preservingTabState: !discardState)
        if discardState { discardArchivedTabState(matching: assignment) }
        return true
    }

    func unloadPages(in spaceID: UUID) {
        let nativeTabIDs = nativeTabs.tabIDs(in: spaceID)
        nativeTabs.remove(in: spaceID)
        let tabIDs = Set(runtimes.compactMap { $0.value.page.spaceID == spaceID ? $0.key : nil })
        releasePages(for: tabIDs.union(nativeTabIDs))
    }

    /// Lets go of the tab's page and native content, keeping its engine state
    /// when `preservingTabState`.
    func evictPage(_ tabID: UUID, preservingTabState: Bool = true) {
        nativeTabs.remove(tabID)
        dropPresentation(tabID)
        if preservingTabState { archiveTabState(for: tabID) }
        guard let runtime = runtimes.removeValue(forKey: tabID) else { return }
        runtime.release(keepingState: preservingTabState)
    }

    /// Releases the pages of `tabIDs`, saying for `kept` that their state was
    /// archived first, and answers what shows each page went.
    @discardableResult
    func releasePages(
        for tabIDs: Set<UUID>, keepingStateOf kept: Set<UUID> = []
    ) -> [BrowserSpaceDataReleaseProbe] {
        var probes: [BrowserSpaceDataReleaseProbe] = []
        for tabID in tabIDs {
            let runtime = runtimes.removeValue(forKey: tabID)
            dropPresentation(tabID)
            guard let runtime else { continue }
            probes.append(contentsOf: runtime.allPages.map { BrowserSpaceDataReleaseProbe($0) })
            runtime.release(keepingState: kept.contains(tabID))
        }
        return probes
    }

    /// The core unloaded the tab's page under memory pressure: its engine
    /// already closed the page, handing the core what brings it back, which
    /// the tab's next page restores.
    func pageUnloaded(_ unloaded: PageUnloaded) {
        let tabID = unloaded.tabID
        guard let runtime = runtimes[tabID], runtime.page.corePage.id == unloaded.pageID else { return }
        runtimes.removeValue(forKey: tabID)
        dropPresentation(tabID)
        runtime.unloaded()
    }

    /// Releases what memory pressure takes back that the core does not decide:
    /// leased pages, only inactive ones on a warning, and on critical pressure
    /// the native content of tabs no window shows. The core unloads tabs'
    /// pages itself once the platform reports the pressure.
    func relieveMemoryPressure(_ level: MemoryPressureLevel, presenting presented: [UUID]) {
        guard level == .critical else { return }
        for tabID in nativeTabs.inactiveTabIDs(excluding: presented) {
            evictPage(tabID)
        }
    }

    // MARK: - Actions - Data

    /// Lets go of every page of `space` or its profile, and of its native
    /// content, and waits until nothing shows them.
    func releasePages(of space: BrowserSpaceRuntimeAssignment) async {
        let nativeTabIDs = nativeTabs.tabIDs(in: space.spaceID)
        nativeTabs.remove(in: space.spaceID)
        let tabIDs = Set(
            runtimes.compactMap { tabID, runtime in
                runtime.page.spaceID == space.spaceID || runtime.page.profileID == space.profileID ? tabID : nil
            }
        ).union(nativeTabIDs)
        let probes = releasePages(for: tabIDs)
        await BrowserSpaceDataReleaseBarrier.waitForRetainedViews(probes)
    }

    /// Deletes what the host keeps of `space` before the Space goes: `release`
    /// lets go of its pages and what the platform keeps besides, then WebKit
    /// erases its profile through `core`, `ephemeral` when this launch
    /// keeps it in memory only. Throws when WebKit could not erase it.
    func deleteData(
        for space: BrowserSpaceRuntimeAssignment, on core: CrestCore, ephemeral: Bool, release: () async -> Void
    ) async throws {
        guard spacesDeletingData.insert(space.spaceID).inserted else { return }
        defer { spacesDeletingData.remove(space.spaceID) }
        await release()
        await BrowserFaviconFallbackLoader.shared.removeAll(for: space.profileID)
        // Nothing may outlive the profile it describes.
        tabState.removeStates(profileID: space.profileID)
        // WebKit erases even an idle profile before its Space is removed.
        let erased = await core.deleteData(
            DeleteProfileData(profileID: space.profileID, ephemeral: ephemeral))
        guard erased else { throw BrowserSpaceDeletionError.dataNotErased }
    }

    /// Lets go of every page a private workspace kept.
    func closePrivateBrowsingSession() {
        releasePages(for: Set(runtimes.keys).union(nativeTabs.tabIDs))
        nativeTabs.reconcile(validTabIDs: [])
    }

    // MARK: - Actions - Leases

}
extension BrowserTabRuntimeAssignment {
    /// Tab `tabID` of the Space `space` names, in its profile.
    init(tabID: UUID, in space: BrowserSpaceRuntimeAssignment) {
        self.init(tabID: tabID, spaceID: space.spaceID, profileID: space.profileID)
    }
}
