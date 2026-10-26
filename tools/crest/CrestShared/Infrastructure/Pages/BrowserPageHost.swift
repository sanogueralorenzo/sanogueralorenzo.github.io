import Foundation
import Observation

/// The pages the core opened for a workspace's tabs and transient requests
/// that this platform hosts: each tab's page while it stays resident, the
/// Quick Window and Peek pages leased for a while, and the state a tab's page
/// leaves behind when it goes. The core decides which pages open, move and
/// unload; windows present what the host keeps. Every window over one
/// workspace on the Mac shares its host; a phone or tablet scene has its own.
@Observable
@MainActor
final class BrowserPageHost {
    // MARK: - Types

    /// One Peek's lease, kept while the Peek asks for the same request.
    private typealias PeekLease = (request: BrowserPeekRequest, lease: BrowserPlatformTransientPageLease)

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
    @ObservationIgnored private(set) var transientLeases: [UUID: WeakBrowserTransientPageLease] = [:]
    @ObservationIgnored private var peekLeases: [UUID: PeekLease] = [:]
    /// The pages the core adopted as windows pages asked for, by page, until
    /// the Quick Window that shows each takes it. Every window over the
    /// workspace shares them, so the Quick Window finds its page whichever
    /// window's pool it opens over.
    @ObservationIgnored private var popupWindowPages: [UUID: BrowserPlatformPage] = [:]

    // MARK: - Initializers

    /// A host whose tabs leave their state in `archive`, or keep none.
    init(archive: (any BrowserTabStateArchiving)? = nil) {
        tabState = BrowserTabStateCoordinator(archive: archive)
    }

    // MARK: - Actions - Resident pages

    /// Every tab's resident page.
    var residentPages: [BrowserPlatformPage] { runtimes.values.map(\.page) }

    /// Every page the host keeps: the tabs', the leases' and the popup
    /// windows' waiting for their Quick Window.
    var livePages: [BrowserPlatformPage] {
        runtimes.values.flatMap(\.allPages) + transientLeases.values.compactMap { $0.value?.page }
            + popupWindowPages.values
    }

    // MARK: - Actions - Popup windows

    /// Keeps `page`, which the core adopted for a window a page asked for,
    /// until its Quick Window takes it; false when the host already keeps it.
    func keepPopupWindowPage(_ page: BrowserPlatformPage) -> Bool {
        guard popupWindowPages[page.corePage.id] == nil else { return false }
        popupWindowPages[page.corePage.id] = page
        return true
    }

    /// The popup window's page `pageID` names, which leaves the host for the
    /// Quick Window that shows it; nil when the host keeps no such page.
    func takePopupWindowPage(_ pageID: UUID) -> BrowserPlatformPage? {
        popupWindowPages.removeValue(forKey: pageID)
    }

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

    /// The icon of the tab's resident page, with the accent its site's theme
    /// gives it; nil when the tab has no page of the Space and profile
    /// `assignment` names, or it went while the icon loaded.
    func pullFavicon(
        for tabID: UUID, matching assignment: BrowserSpaceRuntimeAssignment? = nil
    ) async -> (data: Data, iconAccent: BrowserTabIconAccent?)? {
        guard let page = runtimes[tabID]?.page,
            assignment.map({ page.spaceID == $0.spaceID && page.profileID == $0.profileID }) ?? true,
            let data = await page.pullFavicon(),
            runtimes[tabID]?.page === page
        else { return nil }
        return (data, page.siteThemeIconAccent)
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

    /// Brings the resident pages in line with `workspace` in the read model,
    /// whose tabs wear the icons `images` keeps: pages whose tab is gone or
    /// moved go, a closed tab's state is kept first, and every page takes its
    /// tab's context and its Space's password preference. A workspace the
    /// core no longer holds keeps no page.
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
        reconcileCredentialAccess(in: workspace)
    }

    /// Brings every resident and leased page in line with its Space's "save
    /// passwords" preference: a background tab can hold a pending save offer,
    /// and a Peek runs a page with no tab of its own.
    func reconcileCredentialAccess(in workspace: WorkspaceModel?) {
        let enabledBySpaceID = Dictionary(
            uniqueKeysWithValues: (workspace?.spaces.models ?? []).map {
                ($0.id, $0.settings.credentialPreferences.isEnabled)
            })
        for page in runtimes.values.lazy.map(\.page) {
            page.setCredentialAccessEnabled(enabledBySpaceID[page.spaceID] ?? false)
        }
        pruneTransientLeases()
        for lease in transientLeases.values.compactMap(\.value) {
            lease.setCredentialAccessEnabled(enabledBySpaceID[lease.spaceID] ?? false)
        }
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

    /// Releases a Space's resident and leased pages without keeping their
    /// state. Switching or locking a Space keeps its pages resident.
    func unloadPages(in spaceID: UUID) {
        let nativeTabIDs = nativeTabs.tabIDs(in: spaceID)
        nativeTabs.remove(in: spaceID)
        let tabIDs = Set(runtimes.compactMap { $0.value.page.spaceID == spaceID ? $0.key : nil })
        releasePages(for: tabIDs.union(nativeTabIDs))
        releaseTransientPages(in: spaceID)
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
        releaseTransientPages(for: level)
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
        let probes = releasePages(for: tabIDs) + releaseTransientPages(in: space.spaceID)
        await BrowserSpaceDataReleaseBarrier.waitForRetainedViews(probes)
    }

    /// Deletes what the host keeps of `space` before the Space goes: `release`
    /// lets go of its pages and what the platform keeps besides, then every
    /// engine erases its profile through `core`, `ephemeral` when this launch
    /// keeps it in memory only. Throws when an engine could not erase it.
    func deleteData(
        for space: BrowserSpaceRuntimeAssignment, on core: CrestCore, ephemeral: Bool, release: () async -> Void
    ) async throws {
        guard spacesDeletingData.insert(space.spaceID).inserted else { return }
        defer { spacesDeletingData.remove(space.spaceID) }
        await release()
        await BrowserFaviconFallbackLoader.shared.removeAll(for: space.profileID)
        // Nothing may outlive the profile it describes.
        tabState.removeStates(profileID: space.profileID)
        // Every engine erases the profile, started or not; the Space's
        // deletion finishes only once each has.
        let erased = await core.deleteData(
            DeleteProfileData(requestID: UUID(), profileID: space.profileID, ephemeral: ephemeral))
        guard erased else { throw BrowserSpaceDeletionError.dataNotErased }
    }

    /// Lets go of every page a private workspace kept.
    func closePrivateBrowsingSession() {
        releasePages(for: Set(runtimes.keys).union(nativeTabs.tabIDs))
        nativeTabs.reconcile(validTabIDs: [])
        releaseAllTransientPages()
    }

    // MARK: - Actions - Leases

    var retainedTransientPageCount: Int {
        pruneTransientLeases()
        return transientLeases.values.compactMap(\.value).filter { $0.page != nil }.count
    }

    /// The Peek's lease for `request`: the one it already holds while it can
    /// still show its page, or a new one `makeLease` opens.
    func peekPageLease(
        for request: BrowserPeekRequest,
        makeLease: () -> BrowserPlatformTransientPageLease?
    ) -> BrowserPlatformTransientPageLease? {
        if let entry = peekLeases[request.id], entry.request == request,
            case let lease = entry.lease, lease.assignment == request.assignment,
            lease.page != nil || lease.wasReleasedForMemoryPressure
        {
            return lease
        }
        peekLeases.removeValue(forKey: request.id)?.lease.release()
        let lease = makeLease()
        if let lease { peekLeases[request.id] = (request, lease) }
        return lease
    }

    /// The Peek over tab `tabID` that `isOpen` accepts, which shows in front
    /// of the tab's own page; nil when no such Peek is there. A staged Peek
    /// keeps its lease to draw, but is not open.
    func peekRequest(over tabID: UUID, where isOpen: (BrowserPeekRequest) -> Bool) -> BrowserPeekRequest? {
        peekLeases.values.first { $0.request.sourceTabID == tabID && isOpen($0.request) }?.request
    }

    /// The page of the Peek `peekRequest(over:where:)` finds.
    func peekPage(over tabID: UUID, where isOpen: (BrowserPeekRequest) -> Bool) -> BrowserPlatformPage? {
        peekRequest(over: tabID, where: isOpen).flatMap { peekLeases[$0.id]?.lease.page }
    }

    /// Lets go of the Peeks' leases no longer asked for.
    func retainPeekPages(for requests: [BrowserPeekRequest]) {
        for (id, entry) in peekLeases where !requests.contains(entry.request) {
            peekLeases.removeValue(forKey: id)?.lease.release()
        }
    }

    /// Takes the page `lease` holds for tab `tabID` of `space`, once `prepare`
    /// readied it and the core gave it to the tab through `browser`; nil when
    /// the lease holds no page of that Space, or either refused.
    func adoptTransientPage(
        _ lease: BrowserPlatformTransientPageLease, as tabID: UUID, in space: SpaceModel,
        through browser: BrowserStore,
        prepare: (BrowserPlatformPage) -> Bool
    ) -> BrowserPlatformPage? {
        guard let page = lease.page else { return nil }
        let assignment = BrowserSpaceRuntimeAssignment(space: space)
        guard lease.assignment == assignment, page.spaceID == assignment.spaceID,
            page.profileID == assignment.profileID, prepare(page),
            // The core gives the tab the page only while the tab has none.
            browser.adoptPage(page.corePage, in: space.id, as: tabID)
        else { return nil }
        guard lease.relinquishPage() === page else {
            _ = browser.adoptPage(page.corePage, in: space.id, as: nil)
            return nil
        }
        transientLeases.removeValue(forKey: lease.id)
        return page
    }

    /// Keeps `lease`, which a platform made around a page it already hosts,
    /// as it keeps the leases it makes.
    func keep(_ lease: BrowserPlatformTransientPageLease) {
        transientLeases[lease.id] = WeakBrowserTransientPageLease(lease)
    }

    /// Ends the lease holding `page` when its only navigation turned out to
    /// be a download; false when no lease holds it or the lease keeps it.
    func discardDownloadOnlyTransientPage(_ page: BrowserPlatformPage) -> Bool {
        guard let entry = transientLeases.first(where: { $0.value.value?.page === page }),
            let lease = entry.value.value, lease.discardForDownloadOnlyNavigation()
        else { return false }
        transientLeases.removeValue(forKey: entry.key)
        return true
    }

    /// Whether a lease holds `page`.
    func leases(_ page: BrowserPlatformPage) -> Bool {
        transientLeases.values.contains { $0.value?.page === page }
    }

    /// Every live lease.
    var liveTransientLeases: [BrowserPlatformTransientPageLease] {
        pruneTransientLeases()
        return transientLeases.values.compactMap(\.value)
    }

    func releaseTransientPages(for level: MemoryPressureLevel) {
        for lease in liveTransientLeases where level.releasesActiveTransientPages || !lease.isActive {
            lease.releaseForMemoryPressure()
        }
    }

    @discardableResult
    func releaseTransientPages(in spaceID: UUID) -> [BrowserSpaceDataReleaseProbe] {
        pruneTransientLeases()
        var probes: [BrowserSpaceDataReleaseProbe] = []
        for (id, weakLease) in transientLeases where weakLease.value?.spaceID == spaceID {
            if let page = weakLease.value?.page { probes.append(BrowserSpaceDataReleaseProbe(page)) }
            weakLease.value?.release()
            transientLeases.removeValue(forKey: id)
        }
        return probes
    }

    func releaseAllTransientPages() {
        for lease in transientLeases.values.compactMap(\.value) {
            lease.release()
        }
        transientLeases.removeAll()
        peekLeases.removeAll()
    }

    func pruneTransientLeases() {
        transientLeases = transientLeases.filter { $0.value.value != nil }
    }
}

extension BrowserTabRuntimeAssignment {
    /// Tab `tabID` of the Space `space` names, in its profile.
    init(tabID: UUID, in space: BrowserSpaceRuntimeAssignment) {
        self.init(tabID: tabID, spaceID: space.spaceID, profileID: space.profileID)
    }
}
