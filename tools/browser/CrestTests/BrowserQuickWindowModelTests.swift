import Observation
import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserQuickWindowModelTests: XCTestCase {
    func testWindowTitleFollowsOnlyItsLeaseAndRedactsOnLock() async throws {
        let context = try makeContext()
        context.model.preparePage(isActive: true)
        let page = try XCTUnwrap(context.model.page)
        page.webView.loadHTMLString("<title>Quick page</title>", baseURL: context.model.presentedRequest.url)
        try await waitUntil { page.live.title == "Quick page" && !page.live.isLoading }
        XCTAssertEqual(context.model.windowTitle(for: context.requestBinding.request), "Quick page")
        let selected = try XCTUnwrap(context.browser.shownTab)
        XCTAssertTrue(
            context.browser.setTabCustomTitle("Unrelated selected tab", for: selected.id, in: context.source.id))
        XCTAssertEqual(context.model.windowTitle(for: context.requestBinding.request), "Quick page")
        let changed = expectation(description: "Quick Window observes document title")
        withObservationTracking {
            _ = context.model.windowTitle(for: context.requestBinding.request)
        } onChange: {
            changed.fulfill()
        }
        try await page.webView.evaluateJavaScript("document.title = 'Updated quick page'")
        await fulfillment(of: [changed], timeout: 2)
        XCTAssertEqual(context.model.windowTitle(for: context.requestBinding.request), "Updated quick page")
        context.browser.updateSpaceAccessPolicy(.deviceOwnerAuthentication, in: context.source.id)
        XCTAssertEqual(
            context.model.windowTitle(for: context.requestBinding.request), String(localized: "Quick Window"))
    }

    func testRetargetedSceneRequestRedactsThePreviousPageBeforeModelReconciliation() throws {
        let context = try makeContext()
        let retargeted = context.requestBinding.request.retargeted(
            to: try XCTUnwrap(URL(string: "https://replacement.crest.test")),
            assignment: context.model.presentedRequest.assignment
        )
        XCTAssertEqual(retargeted.id, context.model.presentedRequest.id)
        XCTAssertEqual(context.model.windowTitle(for: retargeted), String(localized: "Quick Window"))
    }

    func testTargetBlankNavigationStaysInTheExactQuickWindowLease() throws {
        let context = try makeContext()
        context.model.preparePage(isActive: true)
        let lease = try XCTUnwrap(context.model.pageLease)
        let page = try XCTUnwrap(lease.page)
        let tabCount = try XCTUnwrap(
            context.browser.shownSpace?.tabs.models.count
        )
        let destination = try XCTUnwrap(
            URL(string: "https://quick-target-blank.crest.test/destination")
        )

        let popupWebView = try page.requestTestPopup(
            url: destination,
            navigationType: .linkActivated
        )

        XCTAssertNil(popupWebView)
        XCTAssertTrue(context.model.pageLease === lease)
        XCTAssertTrue(context.model.page === page)
        XCTAssertEqual(page.navigationReporter?.pendingURL, destination)
        XCTAssertEqual(context.browser.shownSpace?.tabs.models.count, tabCount)
        XCTAssertEqual(
            context.model.presentedRequest.id,
            context.requestBinding.request.id
        )
    }

    func testSwitchingSpacesRejectsLateSourceLeaseMutations() throws {
        let context = try makeContext()
        let model = context.model

        model.preparePage(isActive: true)
        let sourceLease = try XCTUnwrap(model.pageLease)
        model.selectSpace(BrowserSpaceRuntimeAssignment(space: context.destination))

        XCTAssertNil(sourceLease.page)
        XCTAssertNil(model.pageLease)

        XCTAssertFalse(model.archivePageIfNeeded())
        XCTAssertTrue(
            context.browser.spaceModel(context.source.id)?.history
                .entries.isEmpty == true
        )
        XCTAssertTrue(
            context.browser.spaceModel(context.destination.id)?.history
                .entries.isEmpty == true
        )
        XCTAssertTrue(
            context.browser.spaceModel(context.destination.id)?
                .archive.entries.isEmpty == true
        )
    }

    func testClosingArchivesOnlyTheCurrentLeaseInItsExactSpace() throws {
        let context = try makeContext()
        let model = context.model

        model.preparePage(isActive: true)

        XCTAssertTrue(model.archivePageIfNeeded())
        XCTAssertEqual(
            context.browser.spaceModel(context.source.id)?
                .archive.entries.count,
            1
        )
        XCTAssertTrue(
            context.browser.spaceModel(context.destination.id)?
                .archive.entries.isEmpty == true
        )
    }

    func testReplacementProfileInvalidatesTheLeaseWithoutRetargeting() throws {
        // A profile is replaced only in a persistent workspace, by the cloud.
        let context = try makeContext(browsingMode: .standard)
        let model = context.model
        model.preparePage(isActive: true)
        let lease = try XCTUnwrap(model.pageLease)
        context.browser.replaceProfileForTesting(of: context.source.id)
        let replacement = try XCTUnwrap(context.browser.spaceModel(context.source.id))

        model.preparePage(isActive: true)

        XCTAssertNil(lease.page)
        XCTAssertNil(model.pageLease)
        XCTAssertNil(model.spaceModel)
        XCTAssertFalse(model.archivePageIfNeeded())
        XCTAssertFalse(model.promote(to: BrowserSpaceRuntimeAssignment(space: replacement)))
        XCTAssertEqual(model.selectedAssignment.profileID, context.source.profileID)
    }

    func testPermanentlyInvalidatedLeaseIsRebuiltForTheSameAssignment() throws {
        let context = try makeContext()
        let model = context.model
        model.preparePage(isActive: true)
        let invalidatedLease = try XCTUnwrap(model.pageLease)

        context.pages.unloadPages(in: context.source.id)
        model.preparePage(isActive: true)

        let replacementLease = try XCTUnwrap(model.pageLease)
        XCTAssertFalse(replacementLease === invalidatedLease)
        XCTAssertNotNil(replacementLease.page)
        XCTAssertEqual(replacementLease.assignment, invalidatedLease.assignment)
    }

    func testMemoryPressureReleasedLeaseWaitsForExplicitRestore() throws {
        let context = try makeContext()
        let model = context.model
        model.preparePage(isActive: true)
        let releasedLease = try XCTUnwrap(model.pageLease)

        releasedLease.releaseForMemoryPressure()
        model.preparePage(isActive: true)

        XCTAssertTrue(model.pageLease === releasedLease)
        XCTAssertNil(releasedLease.page)
        XCTAssertTrue(releasedLease.wasReleasedForMemoryPressure)
    }

    func testRelockedQuickWindowDismissalArchivesItsValueSnapshot() throws {
        let context = try makeContext()
        context.model.preparePage(isActive: true)
        let lease = try XCTUnwrap(context.model.pageLease)

        context.model.releaseForUnavailableSpace()
        XCTAssertNil(lease.page)
        XCTAssertNil(context.model.pageLease)
        XCTAssertEqual(
            context.model.releasedPageSnapshot?.assignment,
            BrowserSpaceRuntimeAssignment(space: context.source)
        )

        context.model.releaseForDismissal()

        XCTAssertEqual(
            context.browser.spaceModel(context.source.id)?.archive.entries.count,
            1
        )
        XCTAssertNil(context.model.releasedPageSnapshot)
    }

    func testDeletingSourceCannotArchiveItsRetainedValueSnapshot() throws {
        let context = try makeContext()
        context.model.preparePage(isActive: true)
        context.model.releaseForUnavailableSpace()
        XCTAssertNotNil(context.model.releasedPageSnapshot)
        XCTAssertTrue(context.browser.family.beginDeletingSpace(context.source.id))
        defer { context.browser.family.finishDeletingSpace(context.source.id) }

        context.model.releaseForDismissal()

        XCTAssertTrue(
            context.browser.spaceModel(context.source.id)?.archive.entries.isEmpty
                == true
        )
        XCTAssertNil(context.model.releasedPageSnapshot)
    }

    func testUnlockingRelockedQuickWindowRebuildsFromItsValueSnapshot() async throws {
        let context = try makeContext()
        context.model.preparePage(isActive: true)
        let originalLease = try XCTUnwrap(context.model.pageLease)
        context.browser.updateSpaceAccessPolicy(.deviceOwnerAuthentication, in: context.source.id)
        let lockedSource = try XCTUnwrap(context.browser.spaceModel(context.source.id))
        context.model.releaseForUnavailableSpace()

        context.model.preparePage(isActive: true)
        context.model.restorePage()
        XCTAssertNil(context.model.pageLease)
        XCTAssertEqual(
            context.model.releasedPageSnapshot?.assignment,
            BrowserSpaceRuntimeAssignment(space: context.source)
        )

        let didUnlock = await context.spaceAccess.unlock(lockedSource)
        XCTAssertTrue(didUnlock)
        context.model.preparePage(isActive: true)

        let rebuiltLease = try XCTUnwrap(context.model.pageLease)
        XCTAssertFalse(rebuiltLease === originalLease)
        XCTAssertEqual(
            rebuiltLease.assignment,
            BrowserSpaceRuntimeAssignment(space: context.source)
        )
        XCTAssertNil(context.model.releasedPageSnapshot)
    }

    func testRelockedSourceRejectsLatePromotionAndRestore() throws {
        let context = try makeContext()
        context.model.preparePage(isActive: true)
        let lease = try XCTUnwrap(context.model.pageLease)
        context.browser.updateSpaceAccessPolicy(.deviceOwnerAuthentication, in: context.source.id)

        XCTAssertFalse(context.model.promote(to: BrowserSpaceRuntimeAssignment(space: context.destination)))
        XCTAssertEqual(
            context.browser.spaceModel(context.destination.id)?.tabs.models.count,
            context.destination.tabs.count
        )

        let rejectedURL = try XCTUnwrap(
            URL(string: "https://locked-source.crest.test/rejected")
        )
        let presentedRequest = context.model.presentedRequest
        context.model.open(rejectedURL, isActive: true)
        XCTAssertEqual(context.model.presentedRequest, presentedRequest)
        XCTAssertTrue(context.model.pageLease === lease)

        lease.releaseForMemoryPressure()
        context.model.restorePage()
        XCTAssertNil(lease.page)
        XCTAssertNil(context.model.pageLease)
        context.model.preparePage(isActive: true)
        XCTAssertNil(context.model.pageLease)
        XCTAssertEqual(
            context.model.releasedPageSnapshot?.assignment,
            BrowserSpaceRuntimeAssignment(space: context.source)
        )
    }

    /// The core records the Quick Window page's visit in the Space it
    /// browses, and the recorded navigation counts as activity.
    func testCompletedNavigationRecordsOneVisitOnlyInTheExactSourceSpace() async throws {
        let context = try makeContext()
        context.model.preparePage(isActive: true)
        let page = try XCTUnwrap(context.model.page)
        let activity = context.model.activityClock.revision
        let historyURL = try XCTUnwrap(
            URL(string: "https://quick-history.crest.test/completed")
        )

        page.webView.loadHTMLString(
            "<html><body>Quick Window</body></html>",
            baseURL: historyURL
        )
        try await waitUntil(timeout: .seconds(8)) {
            context.browser.spaceModel(context.source.id)?.history.entries.isEmpty == false
        }
        XCTAssertGreaterThan(context.model.activityClock.revision, activity)

        let sourceHistory = try XCTUnwrap(
            context.browser.spaceModel(context.source.id)?.history
        )
        XCTAssertEqual(sourceHistory.entries.count, 1)
        XCTAssertEqual(sourceHistory.entries.first.flatMap { URL(string: $0.url) }?.host(), historyURL.host())
        XCTAssertEqual(sourceHistory.entries.first?.visitCount, 1)
        XCTAssertTrue(
            context.browser.spaceModel(context.destination.id)?.history.entries.isEmpty
                == true
        )
    }

    func testFailedPromotionLeavesTheLeaseAndSelectionOpen() throws {
        let context = try makeContext()
        let model = context.model
        model.preparePage(isActive: true)
        let lease = try XCTUnwrap(model.pageLease)
        let staleDestination = replacingProfile(of: context.destination)

        XCTAssertFalse(model.promote(to: BrowserSpaceRuntimeAssignment(space: staleDestination)))
        XCTAssertNotNil(lease.page)
        XCTAssertFalse(model.wasPromoted)
        XCTAssertEqual(
            context.browser.selectedSpaceID,
            context.source.id
        )
    }

    func testProtectedDestinationCannotBeSelectedOrPromotedWhileLocked() throws {
        let context = try makeContext()
        context.model.preparePage(isActive: true)
        context.browser.updateSpaceAccessPolicy(.deviceOwnerAuthentication, in: context.destination.id)
        let protectedDestination = try XCTUnwrap(context.browser.spaceModel(context.destination.id))

        XCTAssertFalse(
            context.model.availableSpaceModels.contains {
                $0.id == protectedDestination.id
            }
        )
        context.model.selectSpace(BrowserSpaceRuntimeAssignment(space: protectedDestination))
        XCTAssertEqual(
            context.model.selectedAssignment,
            BrowserSpaceRuntimeAssignment(space: context.source)
        )
        XCTAssertFalse(context.model.promote(to: BrowserSpaceRuntimeAssignment(space: protectedDestination)))
        XCTAssertEqual(
            context.browser.spaceModel(protectedDestination.id)?.tabs.models.count,
            protectedDestination.tabs.models.count
        )
        XCTAssertEqual(context.browser.selectedSpaceID, context.source.id)
    }

    func testCapturedDestinationCannotBeSelectedAfterItRelocks() throws {
        let context = try makeContext()
        let capturedDestination = context.destination
        context.browser.updateSpaceAccessPolicy(.deviceOwnerAuthentication, in: context.destination.id)

        context.model.selectSpace(BrowserSpaceRuntimeAssignment(space: capturedDestination))

        XCTAssertEqual(
            context.model.selectedAssignment,
            BrowserSpaceRuntimeAssignment(space: context.source)
        )
        XCTAssertEqual(context.browser.selectedSpaceID, context.source.id)
    }

    func testDeletingDestinationRejectsCapturedPromotionWithoutMutation() throws {
        let context = try makeContext()
        context.model.preparePage(isActive: true)
        XCTAssertTrue(
            context.browser.family.beginDeletingSpace(context.destination.id)
        )
        defer { context.browser.family.finishDeletingSpace(context.destination.id) }

        XCTAssertFalse(context.model.promote(to: BrowserSpaceRuntimeAssignment(space: context.destination)))
        XCTAssertEqual(
            context.browser.spaceModel(context.source.id)?.tabs.models.count,
            context.source.tabs.count
        )
        XCTAssertEqual(
            context.browser.spaceModel(context.destination.id)?.tabs.models.count,
            context.destination.tabs.count
        )
        XCTAssertEqual(context.browser.selectedSpaceID, context.source.id)
    }

    func testLivePromotionAdoptsOnlyTheExactAssignedPage() throws {
        let context = try makeContext(supportsLivePagePromotion: true)
        let model = context.model
        model.preparePage(isActive: true)
        let promotedPage = try XCTUnwrap(model.pageLease?.page)

        XCTAssertTrue(model.promote(to: BrowserSpaceRuntimeAssignment(space: context.source)))
        XCTAssertTrue(model.wasPromoted)
        XCTAssertTrue(context.pages.activePage === promotedPage)
        XCTAssertEqual(context.pages.activePage?.profileID, context.source.profileID)
        let tabs = context.browser.openTabIDs
        XCTAssertFalse(model.promote(to: BrowserSpaceRuntimeAssignment(space: context.source)))
        model.releaseForDismissal()
        XCTAssertEqual(context.browser.openTabIDs, tabs)
        XCTAssertTrue(context.browser.spaceModel(context.source.id)?.archive.entries.isEmpty == true)
    }

    func testEmptyPromotionSelectsTheExactDestinationWithoutOpeningATab() throws {
        let context = try makeContext(startsEmpty: true)
        let sourceTabCount = context.source.tabs.count
        let destinationTabCount = context.destination.tabs.count

        XCTAssertTrue(context.model.promote(to: BrowserSpaceRuntimeAssignment(space: context.destination)))
        XCTAssertTrue(context.model.wasPromoted)
        XCTAssertEqual(
            context.browser.selectedSpaceID,
            context.destination.id
        )
        XCTAssertEqual(
            context.browser.spaceModel(context.source.id)?.tabs.models.count,
            sourceTabCount
        )
        XCTAssertEqual(
            context.browser.spaceModel(context.destination.id)?.tabs.models.count,
            destinationTabCount
        )
    }

    func testStaleModelCannotOverwriteOrMutateAReplacementQuickWindow() throws {
        let context = try makeContext()
        context.model.preparePage(isActive: true)
        let oldPage = try XCTUnwrap(context.model.page)
        let replacement = BrowserQuickWindowRequest(
            id: UUID(),
            url: context.model.presentedRequest.url,
            spaceAssignment: context.model.presentedRequest.assignment,
            targetWindowID: UUID(),
            sourcePresentation: BrowserPeekSourcePresentation(
                normalizedMinX: 0.1,
                normalizedMinY: 0.2,
                normalizedWidth: 0.3,
                normalizedHeight: 0.04,
                label: "Replacement"
            )
        )
        context.requestBinding.request = replacement
        let sourceTabs = context.source.tabs.count
        let destinationTabs = context.destination.tabs.count
        let rejectedURL = try XCTUnwrap(
            URL(string: "https://stale-quick-window.crest.test/rejected")
        )

        context.model.open(rejectedURL, isActive: true)
        context.model.selectSpace(BrowserSpaceRuntimeAssignment(space: context.destination))
        XCTAssertFalse(context.model.promote(to: BrowserSpaceRuntimeAssignment(space: context.destination)))
        context.model.updatePresentedURL(rejectedURL)
        context.model.preparePage(isActive: true)
        context.model.restorePage()

        XCTAssertTrue(
            context.requestBinding.request.hasSamePresentationIdentity(
                as: replacement
            )
        )
        XCTAssertNotEqual(oldPage.live.documentURL, rejectedURL)
        XCTAssertEqual(
            context.model.selectedAssignment,
            BrowserSpaceRuntimeAssignment(space: context.source)
        )
        XCTAssertEqual(
            context.browser.spaceModel(context.source.id)?.tabs.models.count,
            sourceTabs
        )
        XCTAssertEqual(
            context.browser.spaceModel(context.destination.id)?.tabs.models.count,
            destinationTabs
        )
        XCTAssertNil(context.model.pageLease)
        XCTAssertNotNil(context.model.releasedPageSnapshot)

        context.model.releaseForDismissal()
        context.model.releaseForDismissal()

        XCTAssertEqual(
            context.browser.spaceModel(context.source.id)?.archive.entries.count,
            1
        )
        XCTAssertTrue(
            context.requestBinding.request.hasSamePresentationIdentity(
                as: replacement
            )
        )
    }

    private func makeContext(
        startsEmpty: Bool = false,
        supportsLivePagePromotion: Bool = false,
        browsingMode: BrowserBrowsingMode = .privateBrowsing
    ) throws -> QuickWindowTestContext {
        let source = makeSpace(name: "Source")
        let destination = makeSpace(name: "Destination")
        let browser = BrowserStore(
            seed: SessionState.Seed(spaces: [source, destination]),
            credentialVault: InMemoryCredentialVault(),
            browsingMode: browsingMode,
            core: .hostingPages()
        )
        let pages = BrowserPagePool(
            browser: browser,
            browsingMode: browsingMode,
            usesEphemeralWebsiteDataStores: true,
            openNewTab: { url in
                _ = browser.openNewTab(url: url)
            }
        )
        let assignment = BrowserSpaceRuntimeAssignment(space: source)
        let request =
            startsEmpty
            ? BrowserQuickWindowRequest.empty(spaceAssignment: assignment)
            : BrowserQuickWindowRequest(
                url: try XCTUnwrap(URL(string: "about:blank")),
                spaceAssignment: assignment
            )
        let requestBinding = QuickWindowRequestBinding(request: request)
        let spaceAccess = BrowserSpaceAccessController(
            authenticator: BrowserPreviewAuthenticator(result: true)
        )
        // The core refuses a locked Space's pages through the same grants.
        browser.attachSpaceAccess(spaceAccess)
        let model = BrowserQuickWindowModel(
            request: request,
            browser: browser,
            pages: pages,
            spaceAccess: spaceAccess,
            supportsLivePagePromotion: supportsLivePagePromotion,
            preferences: .isolated,
            requestLifecycle: requestBinding.lifecycle
        )
        return QuickWindowTestContext(
            source: source,
            destination: destination,
            browser: browser,
            pages: pages,
            spaceAccess: spaceAccess,
            requestBinding: requestBinding,
            model: model
        )
    }

    private func makeSpace(name: String) -> SpaceState.Seed {
        let tab = TabState.Seed.startPage()
        return SpaceState.Seed(
            name: name,
            symbol: "circle",
            accent: .indigo,
            folders: [],
            tabs: [tab]
        )
    }

    private func waitUntil(
        timeout: Duration = .seconds(3),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            guard clock.now < deadline else {
                XCTFail("Timed out waiting for Quick Window state to change.")
                return
            }
            try await Task.sleep(for: .milliseconds(25))
        }
    }

    private func replacingProfile(of source: SpaceState.Seed) -> SpaceState.Seed {
        SpaceState.Seed(
            id: source.id,
            name: source.settings.name,
            symbol: source.settings.symbol,
            accent: source.settings.accent,
            branding: source.settings.branding,
            folders: source.folders,
            tabs: source.tabs,
            archivedTabs: source.archivedTabs,
            history: source.history,
            browsingPreferences: source.settings.browsingPreferences,
            credentialPreferences: source.settings.credentialPreferences,
            accessPolicy: source.settings.accessPolicy,
            isSavedTabsExpanded: source.settings.isSavedTabsExpanded,
            savedTabsExpansionModifiedAt: source.settings.savedTabsExpansionModifiedAt
        )
    }

    private struct QuickWindowTestContext {
        let source: SpaceState.Seed
        let destination: SpaceState.Seed
        let browser: BrowserStore
        let pages: BrowserPagePool
        let spaceAccess: BrowserSpaceAccessController
        let requestBinding: QuickWindowRequestBinding
        let model: BrowserQuickWindowModel
    }

    @MainActor
    private final class QuickWindowRequestBinding {
        var request: BrowserQuickWindowRequest
        var rejectActionReads = false

        init(request: BrowserQuickWindowRequest) {
            self.request = request
        }

        var lifecycle: BrowserQuickWindowRequestLifecycle {
            BrowserQuickWindowRequestLifecycle(
                isCurrent: { [weak self] expected in
                    self?.rejectActionReads == false
                        && self?.request.hasSamePresentationIdentity(as: expected) == true
                },
                replace: { [weak self] expected, revised in
                    guard
                        self?.request.hasSamePresentationIdentity(as: expected)
                            == true
                    else { return false }
                    self?.request = revised
                    return true
                }
            )
        }
    }
}
