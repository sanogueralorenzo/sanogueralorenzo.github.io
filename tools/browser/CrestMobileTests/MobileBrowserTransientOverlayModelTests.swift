import Foundation
import XCTest

@testable import CrestMobile

@MainActor
final class MobileBrowserTransientOverlayModelTests: XCTestCase {
    func testReturningFromTheTabPickerReusesThePeekPage() throws {
        let context = try makeContext()
        XCTAssertTrue(context.model.preparePage(isActive: true))
        let lease = try XCTUnwrap(context.model.pageLease)
        let page = try XCTUnwrap(context.model.page)
        context.browser.selectSpace(context.destination.id)
        context.model.handleDisappearance()
        XCTAssertTrue(lease.page === page)

        context.browser.selectSpace(context.source.id)
        context.browser.selectTab(context.request.sourceTabID)
        let restored = MobileBrowserTransientOverlayModel(
            request: context.request, browser: context.browser, pages: context.pages,
            coordinator: context.coordinator, spaceAccess: context.spaceAccess, preferences: .isolated)
        XCTAssertTrue(restored.preparePage(isActive: true))
        XCTAssertTrue(restored.page === page)
        restored.dismiss()
        context.pages.retainPeekPages(for: context.coordinator.peekRequests)
        XCTAssertNil(lease.page)
    }

    func testReplacementProfileInvalidatesTheExactTransientRuntime() throws {
        let context = try makeContext(browsingMode: .standard)
        context.model.preparePage(isActive: true)
        let lease = try XCTUnwrap(context.model.pageLease)
        context.browser.replaceProfileForTesting(of: context.source.id)
        let replacement = try XCTUnwrap(context.browser.spaceModel(context.source.id))

        context.model.setSourceAvailable(context.model.spaceModel != nil)
        XCTAssertNil(lease.page)
        XCTAssertNil(context.model.pageLease)
        XCTAssertNil(context.coordinator.peekRequest)
        XCTAssertFalse(context.model.promote(to: context.request.assignment))
    }

    func testStaleSourcePromotionCannotMutateEitherSpace() throws {
        let context = try makeContext(browsingMode: .standard)
        context.model.preparePage(isActive: true)
        let lease = try XCTUnwrap(context.model.pageLease)
        context.browser.replaceProfileForTesting(of: context.source.id)
        let replacement = try XCTUnwrap(context.browser.spaceModel(context.source.id))
        let replacementTabCount = replacement.tabs.models.count

        XCTAssertFalse(context.model.promote(to: context.request.assignment))
        XCTAssertEqual(
            context.browser.spaceModel(replacement.id)?.tabs.models.count,
            replacementTabCount
        )
        XCTAssertEqual(
            context.browser.spaceModel(context.destination.id)?.tabs.models.count,
            context.destination.tabs.count
        )
        XCTAssertEqual(context.browser.selectedSpaceID, replacement.id)
        XCTAssertNotNil(lease.page)
        XCTAssertEqual(context.coordinator.peekRequest, context.request)
    }

    func testSameSpacePromotionAdoptsTheExactTransientPage() throws {
        let context = try makeContext()
        context.model.preparePage(isActive: true)
        let promotedPage = try XCTUnwrap(context.model.pageLease?.page)

        XCTAssertTrue(
            context.model.promote(
                to: BrowserSpaceRuntimeAssignment(space: context.source)
            )
        )
        XCTAssertTrue(context.model.wasPromoted)
        XCTAssertTrue(context.pages.activePage === promotedPage)
        XCTAssertEqual(context.pages.activePage?.profileID, context.source.profileID)
        XCTAssertNil(context.coordinator.peekRequest)
    }

    func testCrossSpacePromotionRebuildsUnderTheDestinationProfile() throws {
        let context = try makeContext()
        context.model.preparePage(isActive: true)
        let sourcePage = try XCTUnwrap(context.model.pageLease?.page)

        XCTAssertTrue(
            context.model.promote(
                to: BrowserSpaceRuntimeAssignment(space: context.destination)
            )
        )
        XCTAssertTrue(context.model.wasPromoted)
        XCTAssertNil(context.model.pageLease?.page)
        XCTAssertFalse(context.pages.activePage === sourcePage)
        XCTAssertEqual(
            context.pages.activePage?.profileID,
            context.destination.profileID
        )
    }

    func testMemoryPressureReleaseRemainsExplicitlyRestorable() throws {
        let context = try makeContext()
        context.model.preparePage(isActive: true)
        let lease = try XCTUnwrap(context.model.pageLease)

        lease.releaseForMemoryPressure()
        XCTAssertTrue(context.model.preparePage(isActive: true))
        XCTAssertTrue(context.model.pageLease === lease)
        XCTAssertNil(lease.page)

        context.model.restorePage()
        XCTAssertNotNil(lease.page)
    }

    func testRestoredPageRecordsTheSameExactHTTPSVisitAsANewPageGeneration() async throws {
        let context = try makeContext()
        context.model.preparePage(isActive: true)
        let lease = try XCTUnwrap(context.model.pageLease)
        let originalPage = try XCTUnwrap(context.model.page)
        let historyURL = try XCTUnwrap(
            URL(string: "https://peek-history.crest.test/restored")
        )
        let originalStartingCount = originalPage.completedNavigationCount
        originalPage.webView.loadHTMLString(
            "<html><body>Original Peek</body></html>",
            baseURL: historyURL
        )
        try await waitUntil(timeout: .seconds(8)) {
            originalPage.completedNavigationCount > originalStartingCount
                && context.browser.spaceModel(context.source.id)?.history.entries.first?.visitCount == 1
        }

        lease.releaseForMemoryPressure()
        context.model.restorePage()
        let restoredPage = try XCTUnwrap(context.model.page)
        let restoredStartingCount = restoredPage.completedNavigationCount
        restoredPage.webView.loadHTMLString(
            "<html><body>Restored Peek</body></html>",
            baseURL: historyURL
        )
        try await waitUntil(timeout: .seconds(8)) {
            restoredPage.completedNavigationCount > restoredStartingCount
                && context.browser.spaceModel(context.source.id)?.history.entries.first?.visitCount == 2
        }

        let sourceHistory = try XCTUnwrap(
            context.browser.spaceModel(context.source.id)?.history.entries
        )
        XCTAssertEqual(sourceHistory.count, 1)
        XCTAssertEqual(sourceHistory.first.flatMap { URL(string: $0.url) }?.host(), historyURL.host())
        XCTAssertEqual(sourceHistory.first?.visitCount, 2)
        XCTAssertTrue(
            context.browser.spaceModel(context.destination.id)?.history.entries.isEmpty
                == true
        )
    }

    func testRelockingTheSourceReleasesItsPageWithoutDismissingTheRequest() throws {
        let context = try makeContext()
        context.model.preparePage(isActive: true)
        let lease = try XCTUnwrap(context.model.pageLease)

        context.model.setSourceLocked(true)

        XCTAssertNil(lease.page)
        XCTAssertNil(context.model.pageLease)
        XCTAssertEqual(context.coordinator.peekRequest, context.request)
        XCTAssertTrue(
            context.browser.spaceModel(context.source.id)?.archive.entries.isEmpty
                == true
        )
    }

    func testReplacementDestinationProfileRejectsTheCapturedMenuAssignment() throws {
        let context = try makeContext(browsingMode: .standard)
        context.model.preparePage(isActive: true)
        let destinationAssignment = BrowserSpaceRuntimeAssignment(
            space: context.destination
        )
        context.browser.replaceProfileForTesting(of: context.destination.id)
        let replacement = try XCTUnwrap(context.browser.spaceModel(context.destination.id))
        let replacementTabCount = replacement.tabs.models.count

        XCTAssertFalse(context.model.promote(to: destinationAssignment))
        XCTAssertEqual(
            context.browser.spaceModel(replacement.id)?.tabs.models.count,
            replacementTabCount
        )
        XCTAssertEqual(context.coordinator.peekRequest, context.request)
    }

    func testLockedDestinationRejectsTheCapturedMenuAssignment() throws {
        let context = try makeContext()
        context.model.preparePage(isActive: true)
        let destinationAssignment = BrowserSpaceRuntimeAssignment(
            space: context.destination
        )
        context.browser.updateSpaceAccessPolicy(.deviceOwnerAuthentication, in: context.destination.id)
        let lockedDestination = try XCTUnwrap(context.browser.spaceModel(context.destination.id))
        let lockedTabCount = lockedDestination.tabs.models.count

        XCTAssertFalse(context.model.promote(to: destinationAssignment))
        XCTAssertEqual(
            context.browser.spaceModel(lockedDestination.id)?.tabs.models.count,
            lockedTabCount
        )
        XCTAssertEqual(context.coordinator.peekRequest, context.request)
    }

    func testRelockedSourceRejectsLatePromotion() throws {
        let context = try makeContext()
        context.model.preparePage(isActive: true)
        let lease = try XCTUnwrap(context.model.pageLease)
        context.browser.updateSpaceAccessPolicy(.deviceOwnerAuthentication, in: context.source.id)
        let lockedSource = try XCTUnwrap(context.browser.spaceModel(context.source.id))

        XCTAssertFalse(
            context.model.promote(
                to: BrowserSpaceRuntimeAssignment(space: context.destination)
            )
        )
        XCTAssertEqual(
            context.browser.spaceModel(context.destination.id)?.tabs.models.count,
            context.destination.tabs.count
        )
        XCTAssertEqual(context.coordinator.peekRequest, context.request)

        lease.releaseForMemoryPressure()
        context.model.restorePage()
        XCTAssertNil(lease.page)
        XCTAssertNil(context.model.pageLease)
        XCTAssertFalse(context.model.preparePage(isActive: true))
        XCTAssertNil(context.model.pageLease)
        XCTAssertEqual(context.coordinator.peekRequest, context.request)
    }

    func testRelockedCapturedSwitchDestinationCannotChangeSpaces() throws {
        let context = try makeContext()
        let assignment = BrowserSpaceRuntimeAssignment(space: context.destination)
        context.browser.updateSpaceAccessPolicy(.deviceOwnerAuthentication, in: context.destination.id)

        context.model.selectLockedSpace(assignment)

        XCTAssertEqual(context.browser.selectedSpaceID, context.source.id)
        XCTAssertEqual(context.coordinator.peekRequest, context.request)
    }

    func testDeletingSourceReleasesAndDismissesItsExactPeekWithoutSideEffects() throws {
        let context = try makeContext()
        context.model.preparePage(isActive: true)
        let lease = try XCTUnwrap(context.model.pageLease)
        XCTAssertTrue(context.browser.family.beginDeletingSpace(context.source.id))
        defer { context.browser.family.finishDeletingSpace(context.source.id) }

        context.model.setSourceAvailable(context.model.spaceModel != nil)

        XCTAssertNil(lease.page)
        XCTAssertNil(context.model.pageLease)
        XCTAssertNil(context.coordinator.peekRequest)
        XCTAssertTrue(
            context.browser.spaceModel(context.source.id)?.history.entries.isEmpty
                == true
        )
        XCTAssertTrue(
            context.browser.spaceModel(context.source.id)?.archive.entries.isEmpty
                == true
        )
    }

    func testDeletingDestinationRejectsCapturedPromotionWithoutMutation() throws {
        let context = try makeContext()
        context.model.preparePage(isActive: true)
        let assignment = BrowserSpaceRuntimeAssignment(space: context.destination)
        XCTAssertTrue(
            context.browser.family.beginDeletingSpace(context.destination.id)
        )
        defer { context.browser.family.finishDeletingSpace(context.destination.id) }

        XCTAssertFalse(context.model.promote(to: assignment))
        XCTAssertEqual(
            context.browser.spaceModel(context.destination.id)?.tabs.models.count,
            context.destination.tabs.count
        )
        XCTAssertEqual(context.browser.selectedSpaceID, context.source.id)
        XCTAssertEqual(context.coordinator.peekRequest, context.request)
    }

    func testQuickWindowRetargetChangesTheRenderedRuntimeIdentity() throws {
        var rememberedSpaceID: UUID?
        var rememberedURL: URL?
        let source = makeSpace(name: "Source")
        let destination = makeSpace(name: "Destination")
        let browser = BrowserStore(
            seed: SessionState.Seed(spaces: [source, destination]),
            showing: source.id, tabs: [source.id: source.tabs[0].id, destination.id: destination.tabs[0].id],
            credentialVault: InMemoryCredentialVault(),
            browsingMode: .privateBrowsing,
            core: .hostingPages()
        )
        let pages = MobileBrowserPageStore(
            browser: browser,
            browsingMode: .privateBrowsing,
            usesEphemeralWebsiteDataStores: true
        )
        let request = BrowserQuickWindowRequest(
            url: try XCTUnwrap(URL(string: "about:blank")),
            spaceAssignment: BrowserSpaceRuntimeAssignment(space: source)
        )
        let coordinator = BrowserTransientBrowsingCoordinator()
        coordinator.presentQuickWindow(request)
        let model = MobileBrowserTransientOverlayModel(
            request: request,
            browser: browser,
            pages: pages,
            coordinator: coordinator,
            spaceAccess: BrowserSpaceAccessController(
                authenticator: BrowserPreviewAuthenticator(result: false)
            ),
            preferences: BrowserTransientBrowsingPreferences(
                archiveLifetime: nil,
                rememberSpace: { spaceID, url in
                    rememberedSpaceID = spaceID
                    rememberedURL = url
                }
            )
        )
        model.preparePage(isActive: true)
        let originalIdentity = request.renderIdentity

        model.selectLockedSpace(
            BrowserSpaceRuntimeAssignment(space: destination)
        )

        let retargeted = try XCTUnwrap(coordinator.quickWindowRequest)
        XCTAssertEqual(retargeted.id, request.id)
        XCTAssertEqual(
            retargeted.assignment,
            BrowserSpaceRuntimeAssignment(space: destination)
        )
        XCTAssertNotEqual(
            retargeted.renderIdentity,
            originalIdentity
        )
        XCTAssertNil(model.pageLease)
        XCTAssertEqual(rememberedSpaceID, destination.id)
        XCTAssertEqual(rememberedURL, request.url)
        XCTAssertTrue(
            browser.spaceModel(source.id)?.archive.entries.isEmpty == true
        )

        let sourceTabCount = browser.spaceModel(source.id)?.tabs.models.count
        let destinationTabCount = browser.spaceModel(destination.id)?.tabs.models.count
        model.dismiss()
        XCTAssertFalse(
            model.promote(
                to: BrowserSpaceRuntimeAssignment(space: destination)
            )
        )
        model.handleDisappearance()
        XCTAssertEqual(coordinator.quickWindowRequest, retargeted)
        XCTAssertEqual(
            browser.spaceModel(source.id)?.tabs.models.count,
            sourceTabCount
        )
        XCTAssertEqual(
            browser.spaceModel(destination.id)?.tabs.models.count,
            destinationTabCount
        )
        XCTAssertTrue(
            browser.spaceModel(source.id)?.archive.entries.isEmpty == true
        )
    }

    func testQuickWindowDismissArchivesExactlyOnceInItsSourceAssignment() throws {
        let context = try makeQuickWindowContext()
        context.model.preparePage(isActive: true)

        context.model.dismiss()
        context.model.handleDisappearance()

        XCTAssertNil(context.coordinator.quickWindowRequest)
        XCTAssertEqual(
            context.browser.spaceModel(context.source.id)?.archive.entries.count,
            1
        )
        XCTAssertTrue(
            context.browser.spaceModel(context.destination.id)?.archive.entries.isEmpty
                == true
        )
    }

    func testReplacingAQuickWindowArchivesTheOutgoingExactLeaseOnce() throws {
        let context = try makeQuickWindowContext()
        context.model.preparePage(isActive: true)
        let replacement = BrowserQuickWindowRequest(
            url: try XCTUnwrap(URL(string: "about:srcdoc")),
            spaceAssignment: BrowserSpaceRuntimeAssignment(
                space: context.destination
            )
        )
        context.coordinator.presentQuickWindow(replacement)

        context.model.setActive(false)
        XCTAssertFalse(context.model.preparePage(isActive: false))
        context.model.restorePage()
        XCTAssertNotNil(context.model.releasedPageSnapshot)
        context.model.handleDisappearance()
        context.model.handleDisappearance()

        XCTAssertEqual(context.coordinator.quickWindowRequest, replacement)
        XCTAssertEqual(
            context.browser.spaceModel(context.source.id)?.archive.entries.count,
            1
        )
        XCTAssertTrue(
            context.browser.spaceModel(context.destination.id)?.archive.entries.isEmpty
                == true
        )
    }

    func testCancelledStagedPeekCreatesNoHistoryOrArchive() throws {
        let context = try makeContext()
        context.coordinator.stagePeek(context.request)
        XCTAssertTrue(context.model.preparePage(isActive: true))
        let lease = try XCTUnwrap(context.model.pageLease)

        context.coordinator.cancelStagedPeek(id: context.request.id)
        context.model.handleDisappearance()

        XCTAssertNil(lease.page)
        XCTAssertNil(context.model.pageLease)
        XCTAssertTrue(
            context.browser.spaceModel(context.source.id)?.history.entries.isEmpty
                == true
        )
        XCTAssertTrue(
            context.browser.spaceModel(context.source.id)?.archive.entries.isEmpty
                == true
        )
    }

    func testQuickWindowPromotionNeverArchivesThePromotedPage() throws {
        let context = try makeQuickWindowContext()
        context.model.preparePage(isActive: true)

        XCTAssertTrue(
            context.model.promote(
                to: BrowserSpaceRuntimeAssignment(space: context.source)
            )
        )
        context.model.handleDisappearance()

        XCTAssertTrue(
            context.browser.spaceModel(context.source.id)?.archive.entries.isEmpty
                == true
        )
    }

    func testQuickWindowReplacementProfileCannotArchiveTheStaleLease() throws {
        let context = try makeQuickWindowContext(browsingMode: .standard)
        context.model.preparePage(isActive: true)
        context.browser.replaceProfileForTesting(of: context.source.id)
        let replacement = try XCTUnwrap(context.browser.spaceModel(context.source.id))

        XCTAssertFalse(context.model.preparePage(isActive: true))
        context.model.handleDisappearance()

        XCTAssertTrue(
            context.browser.spaceModel(replacement.id)?.archive.entries.isEmpty
                == true
        )
        XCTAssertNil(context.coordinator.quickWindowRequest)
    }

    func testRelockedQuickWindowDismissalArchivesItsValueSnapshot() throws {
        let context = try makeQuickWindowContext()
        context.model.preparePage(isActive: true)
        let lease = try XCTUnwrap(context.model.pageLease)

        context.model.setSourceLocked(true)
        XCTAssertNil(lease.page)
        XCTAssertNil(context.model.pageLease)
        XCTAssertEqual(
            context.model.releasedPageSnapshot?.assignment,
            context.request.assignment
        )

        context.model.dismiss()
        context.model.handleDisappearance()

        XCTAssertEqual(
            context.browser.spaceModel(context.source.id)?.archive.entries.count,
            1
        )
        XCTAssertNil(context.coordinator.quickWindowRequest)
    }

    func testUnlockingRelockedQuickWindowRebuildsFromItsValueSnapshot() async throws {
        let context = try makeQuickWindowContext()
        context.model.preparePage(isActive: true)
        let originalLease = try XCTUnwrap(context.model.pageLease)
        context.browser.updateSpaceAccessPolicy(.deviceOwnerAuthentication, in: context.source.id)
        let lockedSource = try XCTUnwrap(context.browser.spaceModel(context.source.id))
        context.model.setSourceLocked(true)

        XCTAssertFalse(context.model.preparePage(isActive: true))
        context.model.restorePage()
        XCTAssertNil(context.model.pageLease)
        XCTAssertEqual(
            context.model.releasedPageSnapshot?.assignment,
            context.request.assignment
        )

        let didUnlock = await context.spaceAccess.unlock(lockedSource)
        XCTAssertTrue(didUnlock)
        XCTAssertTrue(context.model.preparePage(isActive: true))

        let rebuiltLease = try XCTUnwrap(context.model.pageLease)
        XCTAssertFalse(rebuiltLease === originalLease)
        XCTAssertEqual(rebuiltLease.assignment, context.request.assignment)
        XCTAssertEqual(rebuiltLease.recoverableURL, context.request.url)
        XCTAssertNil(context.model.releasedPageSnapshot)
    }

    func testSceneDeactivationBeforeLockObservationPreservesTheQuickWindowURL() async throws {
        let context = try makeQuickWindowContext()
        XCTAssertTrue(context.model.preparePage(isActive: true))
        let page = try XCTUnwrap(context.model.page)
        let currentURL = try XCTUnwrap(
            URL(string: "https://quick-window.crest.test/retained")
        )
        let startingCount = page.completedNavigationCount
        page.webView.loadHTMLString(
            "<html><body>Retained Quick Window</body></html>",
            baseURL: currentURL
        )
        try await waitUntil(timeout: .seconds(8)) {
            page.completedNavigationCount > startingCount
                && page.live.documentURL?.host() == currentURL.host()
        }
        context.browser.updateSpaceAccessPolicy(.deviceOwnerAuthentication, in: context.source.id)
        let lockedSource = try XCTUnwrap(context.browser.spaceModel(context.source.id))

        context.model.setActive(false)

        XCTAssertNil(context.model.pageLease)
        XCTAssertEqual(context.model.releasedPageSnapshot?.url.host(), currentURL.host())
        let didUnlock = await context.spaceAccess.unlock(lockedSource)
        XCTAssertTrue(didUnlock)
        XCTAssertTrue(context.model.preparePage(isActive: true))
        XCTAssertEqual(context.model.pageLease?.recoverableURL.host(), currentURL.host())
    }

    func testDeletingQuickWindowSourceDismissesWithoutArchiving() throws {
        let context = try makeQuickWindowContext()
        context.model.preparePage(isActive: true)
        XCTAssertTrue(context.browser.family.beginDeletingSpace(context.source.id))
        defer { context.browser.family.finishDeletingSpace(context.source.id) }

        context.model.setSourceAvailable(context.model.spaceModel != nil)
        context.model.handleDisappearance()

        XCTAssertNil(context.coordinator.quickWindowRequest)
        XCTAssertNil(context.model.pageLease)
        XCTAssertNil(context.model.releasedPageSnapshot)
        XCTAssertTrue(
            context.browser.spaceModel(context.source.id)?.archive.entries.isEmpty
                == true
        )
    }

    func testZeroLifetimeQuickWindowArchivesAndDismissesDeterministically() async throws {
        let preferences = BrowserTransientBrowsingPreferences(
            archiveLifetime: 0,
            rememberSpace: { _, _ in }
        )
        let context = try makeQuickWindowContext(preferences: preferences)
        context.model.preparePage(isActive: true)

        await context.model.autoArchiveAfterInactivity()

        XCTAssertNil(context.coordinator.quickWindowRequest)
        XCTAssertEqual(
            context.browser.spaceModel(context.source.id)?.archive.entries.count,
            1
        )
    }

    private func makeContext(
        didPromote: @escaping () -> Void = {}, browsingMode: BrowserBrowsingMode = .privateBrowsing
    ) throws -> (
        source: SpaceState.Seed,
        destination: SpaceState.Seed,
        browser: BrowserStore,
        pages: MobileBrowserPageStore,
        coordinator: BrowserTransientBrowsingCoordinator,
        request: BrowserPeekRequest,
        spaceAccess: BrowserSpaceAccessController,
        model: MobileBrowserTransientOverlayModel
    ) {
        let source = makeSpace(name: "Source")
        let destination = makeSpace(name: "Destination")
        let browser = BrowserStore(
            seed: SessionState.Seed(spaces: [source, destination]),
            showing: source.id, tabs: [source.id: source.tabs[0].id, destination.id: destination.tabs[0].id],
            credentialVault: InMemoryCredentialVault(),
            browsingMode: browsingMode,
            core: .hostingPages()
        )
        let pages = MobileBrowserPageStore(
            browser: browser,
            browsingMode: browsingMode,
            usesEphemeralWebsiteDataStores: true
        )
        let request = BrowserPeekRequest(
            url: try XCTUnwrap(URL(string: "about:blank")),
            sourceTabID: try XCTUnwrap(source.tabs.first?.id),
            sourceTitle: source.settings.name,
            spaceAssignment: BrowserSpaceRuntimeAssignment(space: source),
            trigger: .longPress
        )
        let coordinator = BrowserTransientBrowsingCoordinator()
        coordinator.presentPeek(request)
        let spaceAccess = BrowserSpaceAccessController(
            authenticator: BrowserPreviewAuthenticator(result: true)
        )
        browser.attachSpaceAccess(spaceAccess)
        return (
            source,
            destination,
            browser,
            pages,
            coordinator,
            request,
            spaceAccess,
            MobileBrowserTransientOverlayModel(
                request: request,
                browser: browser,
                pages: pages,
                coordinator: coordinator,
                spaceAccess: spaceAccess,
                preferences: .isolated,
                didPromote: didPromote
            )
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
                XCTFail("Timed out waiting for transient browser state to change.")
                return
            }
            try await Task.sleep(for: .milliseconds(25))
        }
    }

    private func makeQuickWindowContext(
        preferences: BrowserTransientBrowsingPreferences = .isolated,
        browsingMode: BrowserBrowsingMode = .privateBrowsing
    ) throws -> (
        source: SpaceState.Seed,
        destination: SpaceState.Seed,
        browser: BrowserStore,
        pages: MobileBrowserPageStore,
        coordinator: BrowserTransientBrowsingCoordinator,
        request: BrowserQuickWindowRequest,
        spaceAccess: BrowserSpaceAccessController,
        model: MobileBrowserTransientOverlayModel
    ) {
        let source = makeSpace(name: "Source")
        let destination = makeSpace(name: "Destination")
        let browser = BrowserStore(
            seed: SessionState.Seed(spaces: [source, destination]),
            showing: source.id, tabs: [source.id: source.tabs[0].id, destination.id: destination.tabs[0].id],
            credentialVault: InMemoryCredentialVault(),
            browsingMode: browsingMode,
            core: .hostingPages()
        )
        let pages = MobileBrowserPageStore(
            browser: browser,
            browsingMode: browsingMode,
            usesEphemeralWebsiteDataStores: true
        )
        let request = BrowserQuickWindowRequest(
            url: try XCTUnwrap(URL(string: "about:blank")),
            spaceAssignment: BrowserSpaceRuntimeAssignment(space: source)
        )
        let coordinator = BrowserTransientBrowsingCoordinator()
        coordinator.presentQuickWindow(request)
        let spaceAccess = BrowserSpaceAccessController(
            authenticator: BrowserPreviewAuthenticator(result: true)
        )
        browser.attachSpaceAccess(spaceAccess)
        return (
            source,
            destination,
            browser,
            pages,
            coordinator,
            request,
            spaceAccess,
            MobileBrowserTransientOverlayModel(
                request: request,
                browser: browser,
                pages: pages,
                coordinator: coordinator,
                spaceAccess: spaceAccess,
                preferences: preferences
            )
        )
    }

    private func makeSpace(name: String) -> SpaceState.Seed {
        SpaceState.Seed(name: name, symbol: "circle", accent: .indigo, tabs: [.startPage()])
    }
}
