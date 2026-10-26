import Foundation
import Observation

@Observable
@MainActor
final class MobileBrowserTransientOverlayModel {
    let request: any MobileBrowserTransientRequest
    private(set) var pageLease: MobileBrowserTransientPageLease?
    private(set) var releasedPageSnapshot: BrowserTransientPageSnapshot?
    private(set) var wasPromoted = false

    /// The core page the released snapshot names, unloaded with its state
    /// kept so the core still knows what it showed until the snapshot goes.
    @ObservationIgnored private var unloadedPage: CorePage?
    @ObservationIgnored let browser: BrowserStore
    @ObservationIgnored private let pages: MobileBrowserPageStore?
    @ObservationIgnored let coordinator: BrowserTransientBrowsingCoordinator
    @ObservationIgnored let spaceAccess: BrowserSpaceAccessController
    @ObservationIgnored private let preferences: BrowserTransientBrowsingPreferences
    @ObservationIgnored private let activityClock: BrowserTransientActivityClock
    @ObservationIgnored private let didPromote: () -> Void

    init(
        request: any MobileBrowserTransientRequest,
        browser: BrowserStore,
        pages: MobileBrowserPageStore,
        coordinator: BrowserTransientBrowsingCoordinator,
        spaceAccess: BrowserSpaceAccessController,
        preferences: BrowserTransientBrowsingPreferences,
        didPromote: @escaping () -> Void = {}
    ) {
        self.request = request
        self.browser = browser
        self.pages = pages
        self.coordinator = coordinator
        self.spaceAccess = spaceAccess
        self.preferences = preferences
        self.didPromote = didPromote
        activityClock = BrowserTransientActivityClock()
        browser.core.engines.observeRecords(self) { [weak self] in self?.recordActivity(after: $0) }
        browser.core.followClosedTransientPages(self) { [weak self] in self?.pageClosed($0) }
    }

    init(
        previewing request: any MobileBrowserTransientRequest,
        browser: BrowserStore,
        coordinator: BrowserTransientBrowsingCoordinator,
        spaceAccess: BrowserSpaceAccessController
    ) {
        self.request = request
        self.browser = browser
        pages = nil
        self.coordinator = coordinator
        self.spaceAccess = spaceAccess
        preferences = .isolated
        didPromote = {}
        activityClock = BrowserTransientActivityClock(
            now: Date(timeIntervalSince1970: 0)
        )
    }

    /// The Space the overlay browses, as the read model holds it.
    var spaceModel: SpaceModel? {
        browser.spaceModel(matching: request.spaceAssignment)
    }

    /// The Spaces the overlay may move to or unlock: none being deleted, and
    /// none locked but its own.
    var availableSpaceModels: [SpaceModel] {
        browser.transientSpaces(forRequestIn: request.spaceID, isLocked: spaceAccess.isLocked)
    }

    var page: MobileBrowserPage? {
        pageLease?.page
    }

    var motionState: BrowserPeekMotionState? {
        request.motionState(in: coordinator)
    }

    var isSelected: Bool {
        request.isSelected(in: browser)
    }

    var hasSource: Bool {
        request.hasSource(in: browser)
    }

    /// The inactivity wait a Quick Window restarts when its activity or its
    /// lifetime changes.
    var archiveTimer: BrowserTransientArchiveTimer {
        BrowserTransientArchiveTimer(activity: activityClock.revision, lifetime: preferences.archiveLifetime)
    }

    @discardableResult
    func preparePage(isActive: Bool) -> Bool {
        guard let space = sourceDisposition.settle(on: self) else { return false }
        if let pageLease, pageLease.isReusable(for: request.spaceAssignment) {
            pageLease.setActive(isActive && isSelected)
            return true
        }
        pageLease?.release()
        guard let pages else { return true }
        pageLease = request.makePageLease(for: self, from: pages, in: space)
        guard let pageLease else {
            dismissUnavailableRequest()
            return false
        }
        forgetReleasedSnapshot()
        pageLease.setActive(isActive && isSelected)
        return true
    }

    func setActive(_ isActive: Bool) {
        guard sourceDisposition.settle(on: self) != nil else { return }
        pageLease?.setActive(isActive && isSelected)
        guard isActive else { return }
        activityClock.recordActivity(restartsTimerImmediately: true)
    }

    func setSourceLocked(_ isLocked: Bool) {
        guard isLocked else { return }
        releaseLease()
    }

    func setSourceAvailable(_ isAvailable: Bool) {
        guard !isAvailable else { return }
        dismissUnavailableRequest()
    }

    /// The core closed this request's page: it closed itself, as a page
    /// another page opened may, or its engine closed it. The Peek or Quick
    /// Window goes with it, keeping nothing of it.
    private func pageClosed(_ closed: TransientPageClosed) {
        guard pageLease?.pageID == closed.pageID else { return }
        dismissUnavailableRequest()
    }

    /// A navigation the core recorded for this request's page is activity,
    /// which keeps a Quick Window from archiving itself while in use.
    private func recordActivity(after records: Engines.PageRecords) {
        guard isCurrentRequest, let page = pageLease?.page, records.recordedNavigation(of: page.corePage.id) else {
            return
        }
        activityClock.recordActivity(restartsTimerImmediately: true)
    }

    func recordUserActivity() {
        activityClock.recordActivity()
    }

    func restorePage() {
        activityClock.recordActivity(restartsTimerImmediately: true)
        guard isCurrentRequest else {
            releaseLease()
            return
        }
        guard let pageLease, disposition(ofSpaceMatching: pageLease.assignment).settle(on: self) != nil else {
            return
        }
        pageLease.restore()
    }

    @discardableResult
    func promote(to destinationAssignment: BrowserSpaceRuntimeAssignment) -> Bool {
        activityClock.recordActivity(restartsTimerImmediately: true)
        guard let pages,
            isCurrentRequest,
            !wasPromoted,
            let pageLease,
            let page = pageLease.page,
            let outcome = BrowserTransientPagePromotion(
                page: page.corePage,
                url: page.live.documentURL ?? request.url,
                destinationAssignment: destinationAssignment
            ).perform(
                in: browser,
                isLocked: spaceAccess.isLocked,
                adoptPage: { tabID, destination in
                    pages.adoptTransientPage(pageLease, as: tabID, in: destination)
                }
            )
        else { return false }

        request.rememberKeeping(page, in: destinationAssignment, preferences: preferences)
        wasPromoted = true
        if outcome == .openedNewPage {
            pageLease.release()
            pages.select()
        }
        dismissCoordinatorRequest()
        didPromote()
        return true
    }

    func selectLockedSpace(_ assignment: BrowserSpaceRuntimeAssignment) {
        guard isCurrentRequest else { return }
        request.selectLockedSpace(assignment, on: self)
    }

    func dismiss() {
        dismissCoordinatorRequest()
    }

    func dismissUnavailableRequest() {
        guard isCurrentRequest else { return }
        pageLease?.release()
        pageLease = nil
        forgetReleasedSnapshot()
        request.dismiss(from: coordinator)
    }

    func handleDisappearance() {
        guard !wasPromoted else { return }
        request.disappear(from: self)
        pageLease = nil
        forgetReleasedSnapshot()
    }

    func autoArchiveAfterInactivity() async {
        guard request.isQuickWindow,
            isCurrentRequest,
            let lifetime = preferences.archiveLifetime,
            await activityClock.waitUntilInactive(for: lifetime)
        else { return }
        dismissCoordinatorRequest()
    }

    private func dismissCoordinatorRequest() {
        guard isCurrentRequest else { return }
        request.close(on: self)
    }

    func dismissDownloadOnlyNavigation() {
        guard isCurrentRequest else { return }
        forgetReleasedSnapshot()
        request.dismiss(from: coordinator)
    }

    /// Files a Quick Window's page in the archive. The core archives a page
    /// once, and never one kept as a tab.
    func archiveCurrentSnapshot() {
        guard let snapshot = currentSnapshot else { return }
        browser.archiveTransientPage(snapshot.pageID, matching: snapshot.assignment)
    }

    func changeSpace(
        of quickWindowRequest: BrowserQuickWindowRequest,
        to destinationAssignment: BrowserSpaceRuntimeAssignment
    ) {
        guard isCurrentRequest,
            destinationAssignment.spaceID != quickWindowRequest.spaceID,
            let destination = browser.spaceModel(matching: destinationAssignment),
            !spaceAccess.isLocked(destination)
        else { return }
        let pageURL = currentSnapshot?.url ?? quickWindowRequest.initialURL
        let currentURL = pageURL ?? quickWindowRequest.url
        // Moving a page, not an empty lookup, remembers the Space for its site.
        if let pageURL {
            preferences.rememberSpace(destinationAssignment.spaceID, for: pageURL)
        }
        pageLease?.release()
        pageLease = nil
        forgetReleasedSnapshot()
        coordinator.presentQuickWindow(
            quickWindowRequest.retargeted(
                to: currentURL,
                assignment: destinationAssignment
            )
        )
    }

    var isCurrentRequest: Bool {
        request.isPresented(by: coordinator)
    }

    private var sourceDisposition: BrowserTransientLeaseDisposition {
        disposition(ofSpaceMatching: request.spaceAssignment)
    }

    /// Whether the page may be kept in the Space `assignment` names, and the
    /// Space of the read model its page opens in.
    private func disposition(
        ofSpaceMatching assignment: BrowserSpaceRuntimeAssignment
    ) -> BrowserTransientLeaseDisposition {
        BrowserTransientLeaseDisposition(
            isPresentingRequest: isCurrentRequest,
            space: hasSource ? browser.spaceModel(matching: assignment) : nil,
            isLocked: spaceAccess.isLocked
        )
    }

    /// Lets the page go; a Quick Window keeps what it shows: the snapshot it
    /// archives on dismissal, and the core's memory of the page, both until
    /// the snapshot goes.
    func releaseLease() {
        guard let pageLease else { return }
        request.release(pageLease, on: self)
        self.pageLease = nil
    }

    /// Unloads `lease`'s page, keeping its snapshot and the core's memory of it.
    func unload(_ lease: MobileBrowserTransientPageLease) {
        let retained = snapshot(lease)
        forgetReleasedSnapshot()
        releasedPageSnapshot = retained
        unloadedPage = lease.unload()
    }

    /// Drops the released page's snapshot, and releases its page for good so
    /// the core forgets what it showed too.
    private func forgetReleasedSnapshot() {
        releasedPageSnapshot = nil
        unloadedPage?.release(keepingState: false)
        unloadedPage = nil
    }

    private var currentSnapshot: BrowserTransientPageSnapshot? {
        pageLease.map(snapshot) ?? releasedPageSnapshot
    }

    private func snapshot(
        _ lease: MobileBrowserTransientPageLease
    ) -> BrowserTransientPageSnapshot {
        BrowserTransientPageSnapshot(
            assignment: lease.assignment,
            url: lease.recoverableURL,
            title: lease.page?.live.title,
            pageID: lease.pageID
        )
    }
}

extension MobileBrowserTransientOverlayModel: BrowserTransientLeaseHolder {}
