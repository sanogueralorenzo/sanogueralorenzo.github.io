import SwiftUI
import UIKit
import WebKit
import XCTest

@testable import CrestMobile

@MainActor
final class MobileBrowserNavigationTests: XCTestCase {

    func testMobileFileExportsOfferShareAndSaveToFilesDestinations() {
        XCTAssertEqual(
            MobileBrowserFileExportDestination.all,
            [.share, .files]
        )
        XCTAssertEqual(String(localized: MobileBrowserFileExportDestination.share.title), "Share…")
        XCTAssertEqual(
            String(localized: MobileBrowserFileExportDestination.files.title),
            "Save to Files…"
        )
    }

    /// Toolbar swipes page Split View cards instead. A transition which really
    /// leaves the rendered Space still puts the page away first.
    func testLeavingARenderedSpaceDismissesThePageBeforeTheSwitch() {
        let navigation = MobileBrowserNavigationState()
        navigation.adapt(to: .compact)
        navigation.selectTab()
        navigation.completePagePresentation()
        navigation.hideCompactToolbar()

        navigation.prepareForSpaceSwitch()

        XCTAssertFalse(navigation.compactShowsPage)
        XCTAssertFalse(navigation.compactToolbarIsHidden)
    }

    func testSelectionCannotRecreateAReleasingSpacePage()
        async throws
    {
        let space = makeSpace(index: 99)
        let otherSpace = makeSpace(index: 98)
        let browser = BrowserStore.hostingPages(SessionState.Seed(spaces: [space, otherSpace]))
        let pages = MobileBrowserPageStore(
            browser: browser,
            usesEphemeralWebsiteDataStores: true
        )
        let tabID = try XCTUnwrap(space.tabs.first?.id)
        pages.present(space: space.id)
        var retainedPage: MobileBrowserPage? = try XCTUnwrap(pages.activePage)

        // A window releases a Space's runtime once its deletion has begun.
        try beginDeleting(space.id, in: browser)
        let release = Task {
            await pages.releaseWindowRuntime(for: BrowserSpaceRuntimeAssignment(space: space))
        }
        for _ in 0..<1_000 where pages.containsResidentPage(for: tabID) {
            await Task.yield()
        }
        XCTAssertFalse(pages.containsResidentPage(for: tabID))

        pages.present(space: space.id)

        XCTAssertFalse(pages.containsResidentPage(for: tabID))
        XCTAssertNil(pages.activePage)

        withExtendedLifetime(retainedPage) {}
        retainedPage = nil
        await release.value
    }

    func testMobileSpaceSwitchingRetainsPagesUntilTheirSpaceUnloads() throws {
        let firstSpace = makeSpace(index: 93)
        let secondSpace = makeSpace(index: 94)
        let session = SessionState.Seed(spaces: [firstSpace, secondSpace])
        let pages = MobileBrowserPageStore(
            browser: .hostingPages(session),
            usesEphemeralWebsiteDataStores: true
        )

        pages.present(space: firstSpace.id)
        let firstPage = try XCTUnwrap(pages.activePage)
        pages.present(space: secondSpace.id)

        XCTAssertTrue(pages.containsResidentPage(for: firstPage.tabID))
        XCTAssertTrue(
            pages.containsResidentPage(for: try XCTUnwrap(secondSpace.tabs.first?.id))
        )

        pages.present(space: firstSpace.id)
        XCTAssertTrue(try XCTUnwrap(pages.activePage) === firstPage)

        pages.unloadPages(in: firstSpace.id)

        XCTAssertFalse(pages.containsResidentPage(for: firstPage.tabID))
        XCTAssertTrue(
            pages.containsResidentPage(for: try XCTUnwrap(secondSpace.tabs.first?.id))
        )
    }

    func testPrivateMobilePagesUseDistinctEphemeralStoresAndNoCredentialBridge() throws {
        let browser = BrowserStore.privateBrowsing(core: .hostingPages())
        let pages = MobileBrowserPageStore(
            browser: browser,
            browsingMode: .privateBrowsing,
            usesEphemeralWebsiteDataStores: true
        )

        pages.select()
        let firstPage = try XCTUnwrap(pages.activePage)
        let firstStore = firstPage.webView.configuration.websiteDataStore

        XCTAssertFalse(firstStore.isPersistent)
        XCTAssertNil(firstStore.identifier)
        let privateScripts = firstPage.webView.configuration.userContentController.userScripts
        XCTAssertTrue(privateScripts.contains { $0.source.contains("webkit-playsinline") })

        browser.addSpace()
        pages.select()
        let secondPage = try XCTUnwrap(pages.activePage)
        let secondStore = secondPage.webView.configuration.websiteDataStore

        XCTAssertEqual(browser.shownSpace?.settings.name, "Private 2")
        XCTAssertFalse(firstStore === secondStore)
        XCTAssertEqual(pages.residentPageCount, 2)

        pages.closePrivateBrowsingSession(browser.spaceModels.map(BrowserSpaceRuntimeAssignment.init(space:)))
        browser.resetPrivateBrowsingSession()

        XCTAssertEqual(pages.residentPageCount, 0)
        XCTAssertNil(pages.activePage)
        XCTAssertEqual(browser.shownSpace?.settings.name, "Private")
        XCTAssertEqual(browser.spaceModels.count, 1)
    }

    /// A private window's website data lives only as long as private
    /// browsing does: ending it erases each private profile, so no later page
    /// of the profile finds the store its pages browsed in.
    func testEndingPrivateBrowsingDropsTheStoreItsPagesBrowsedIn() async throws {
        let browser = BrowserStore.privateBrowsing(core: .hostingPages())
        let pages = MobileBrowserPageStore(
            browser: browser,
            browsingMode: .privateBrowsing,
            usesEphemeralWebsiteDataStores: true
        )
        pages.select()
        let privateStore = try XCTUnwrap(pages.activePage).webView.configuration.websiteDataStore

        pages.closePrivateBrowsingSession(browser.spaceModels.map(BrowserSpaceRuntimeAssignment.init(space:)))
        // The erasure runs once the private window's own teardown finished.
        try await Task.sleep(for: .milliseconds(100))
        pages.select()
        let laterStore = try XCTUnwrap(pages.activePage).webView.configuration.websiteDataStore

        XCTAssertFalse(laterStore.isPersistent)
        XCTAssertFalse(laterStore === privateStore)
        pages.closePrivateBrowsingSession(browser.spaceModels.map(BrowserSpaceRuntimeAssignment.init(space:)))
        browser.resetPrivateBrowsingSession()
    }

    func testDownloadConfirmationQueuesConcurrentRequestsWithoutChangingSpaceOwnership() async throws {
        let confirmation = MobileDownloadRiskConfirmationCoordinator()
        let firstAssessment = DownloadRiskAssessment(
            sanitizedFilename: "first.command",
            reasons: [.executableOrInstaller]
        )
        let secondAssessment = DownloadRiskAssessment(
            sanitizedFilename: "second.mobileconfig",
            reasons: [.executableOrInstaller, .dangerousTypeMismatch]
        )

        let firstApproval = Task {
            await confirmation.requestApproval(
                assessment: firstAssessment,
                sourceURL: URL(string: "https://first.crest.test/file"),
                spaceName: "Work",
                profileID: UUID()
            )
        }
        try await waitUntil {
            confirmation.request?.assessment == firstAssessment
        }
        let secondApproval = Task {
            await confirmation.requestApproval(
                assessment: secondAssessment,
                sourceURL: URL(string: "https://second.crest.test/file"),
                spaceName: "Private",
                profileID: UUID()
            )
        }
        await Task.yield()

        XCTAssertEqual(confirmation.request?.assessment, firstAssessment)
        XCTAssertEqual(confirmation.request?.spaceName, "Work")

        confirmation.approve()

        let firstWasApproved = await firstApproval.value
        XCTAssertTrue(firstWasApproved)
        try await waitUntil {
            confirmation.request?.assessment == secondAssessment
        }
        XCTAssertEqual(confirmation.request?.spaceName, "Private")

        confirmation.cancel()

        let secondWasApproved = await secondApproval.value
        XCTAssertFalse(secondWasApproved)
        XCTAssertNil(confirmation.request)
    }

    func testDismissingDownloadConfirmationFailsClosed() async throws {
        let confirmation = MobileDownloadRiskConfirmationCoordinator()
        let assessment = DownloadRiskAssessment(
            sanitizedFilename: "installer.pkg",
            reasons: [.executableOrInstaller]
        )
        let approval = Task {
            await confirmation.requestApproval(
                assessment: assessment,
                sourceURL: nil,
                spaceName: "Personal",
                profileID: UUID()
            )
        }
        try await waitUntil { confirmation.isPresented }

        confirmation.isPresented = false

        let wasApproved = await approval.value
        XCTAssertFalse(wasApproved)
        XCTAssertNil(confirmation.request)
    }

    @MainActor
    func testMobileArchiveAndDownloadsPresentationIsWindowOwned() {
        let firstWindow = MobileBrowserNavigationState()
        let secondWindow = MobileBrowserNavigationState()

        firstWindow.utilityPresentation.present(.archive)

        XCTAssertEqual(firstWindow.utilityPresentation.surface, .archive)
        XCTAssertNil(secondWindow.utilityPresentation.surface)

        firstWindow.utilityPresentation.present(.downloads)

        XCTAssertEqual(firstWindow.utilityPresentation.surface, .downloads)
        XCTAssertNil(secondWindow.utilityPresentation.surface)

        firstWindow.utilityPresentation.dismiss(.archive)
        XCTAssertEqual(firstWindow.utilityPresentation.surface, .downloads)

        firstWindow.utilityPresentation.dismiss(.downloads)
        XCTAssertNil(firstWindow.utilityPresentation.surface)
    }

    func testRegularPresentationDoesNotMutateTheCompactNavigationChoice() {
        let navigation = MobileBrowserNavigationState()
        navigation.adapt(to: .compact)
        navigation.selectTab()

        navigation.adapt(to: .regular)
        XCTAssertFalse(navigation.defersPageActivation)
        navigation.adapt(to: .compact)

        XCTAssertTrue(navigation.compactShowsPage)
        XCTAssertFalse(navigation.defersPageActivation)
    }

    func testSidebarEditingPauseAllowsExplicitDismissalAndResumesTheTimer() async throws {
        let navigation = MobileBrowserNavigationState(
            transientSidebarDismissalDelay: .milliseconds(60)
        )
        navigation.adapt(to: .compact)
        navigation.selectTab()
        navigation.showRegularSidebar()
        navigation.setTransientSidebarDismissalPaused(true)
        navigation.handleRegularSidebarInteraction()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(navigation.regularSidebarPresentation, .floating)

        navigation.handleRegularPageInteraction()
        XCTAssertEqual(navigation.regularSidebarPresentation, .collapsed)

        navigation.showRegularSidebar()
        navigation.setTransientSidebarDismissalPaused(true)
        navigation.setTransientSidebarDismissalPaused(false)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(navigation.regularSidebarPresentation, .collapsed)
    }

    func testSelectingATabDismissesOnlyTheFloatingPhoneSidebar() {
        XCTAssertTrue(
            MobileBrowserPresentation.compact.dismissesSidebarOnTabSelection(
                sidebarPresentation: .floating
            )
        )
        XCTAssertFalse(
            MobileBrowserPresentation.compact.dismissesSidebarOnTabSelection(
                sidebarPresentation: .docked
            )
        )
        XCTAssertFalse(
            MobileBrowserPresentation.regular.dismissesSidebarOnTabSelection(
                sidebarPresentation: .floating
            ),
            "iPad keeps the normal shared floating-sidebar selection behavior."
        )
    }

    func testRegularSidebarPresentationRestoresPerNativeWindow() {
        let hiddenWindow = MobileBrowserNavigationState(
            regularSidebarIsPresented: false
        )
        let visibleWindow = MobileBrowserNavigationState(
            regularSidebarIsPresented: true
        )

        XCTAssertFalse(hiddenWindow.regularSidebarIsPresented)
        XCTAssertTrue(visibleWindow.regularSidebarIsPresented)
    }

    func testMobileHostDeclaresBackgroundModesForPictureInPictureAndCloudSync() throws {
        let backgroundModes = try XCTUnwrap(
            Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]
        )

        XCTAssertEqual(Set(backgroundModes), ["audio", "remote-notification"])
    }

    func testAStaleMobileHostCannotReclaimOrMutateTheReplacementHostsWebView() {
        let oldHost = MobileBrowserWebHostView()
        let newHost = MobileBrowserWebHostView()
        let webView = StopRecordingMobileWebView()

        oldHost.attach(webView)
        newHost.configureViewport(
            MobileBrowserPageViewport(
                obscuresSystemSafeAreas: true,
                systemSafeAreaInsets: .zero,
                bottomChromeHeight: MobileBrowserPageViewport.compactToolbarHeight
            )
        )
        newHost.attach(webView)
        // SwiftUI may still issue updateUIView to the outgoing host while its
        // removal transition runs. Exercise that update before dismantling it.
        oldHost.configureViewport(
            MobileBrowserPageViewport(
                obscuresSystemSafeAreas: true,
                systemSafeAreaInsets: UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0),
                bottomChromeHeight: 100
            )
        )
        oldHost.attach(webView)
        XCTAssertTrue(webView.superview === newHost)
        oldHost.detach(stopsLoading: true)

        XCTAssertTrue(webView.superview === newHost)
        XCTAssertEqual(
            webView.stopLoadingCallCount,
            0,
            "A stale SwiftUI host must not cancel a navigation owned by the replacement host."
        )
        XCTAssertEqual(
            webView.scrollView.verticalScrollIndicatorInsets.bottom,
            MobileBrowserPageViewport.compactToolbarHeight,
            "A stale host must not clear viewport state applied by the replacement host."
        )
    }

    func testAPageReturnsToTheSurvivingHostWhenANewerHostGoesFirst() {
        let survivingHost = MobileBrowserWebHostView()
        let outgoingHost = MobileBrowserWebHostView()
        let webView = StopRecordingMobileWebView()

        // A Start Page turning into a page in a new tab swaps SwiftUI's page
        // subtree, and the outgoing subtree, still re-rendering during its
        // removal, builds a host after the incoming one did.
        survivingHost.attach(webView)
        outgoingHost.attach(webView)
        survivingHost.attach(webView)
        XCTAssertTrue(webView.superview === outgoingHost)

        MobileBrowserWebView.dismantleUIView(outgoingHost, coordinator: MobileBrowserWebView.Coordinator())

        XCTAssertTrue(
            webView.superview === survivingHost,
            "The page must stay on screen in the host SwiftUI keeps."
        )
        XCTAssertEqual(webView.stopLoadingCallCount, 0)
    }

    func testDismantlingMobileWebViewDoesNotCancelModelOwnedNavigation() {
        let host = MobileBrowserWebHostView()
        let coordinator = MobileBrowserWebView.Coordinator()
        let webView = StopRecordingMobileWebView()

        host.attach(webView)
        MobileBrowserWebView.dismantleUIView(host, coordinator: coordinator)

        XCTAssertNil(webView.superview)
        XCTAssertEqual(
            webView.stopLoadingCallCount,
            0,
            "SwiftUI host teardown must not cancel navigation owned by the retained page model."
        )
    }

    // MARK: - Upward reveal routing

    /// The undocked placements only ever have this toolbar to swipe because a
    /// split is on show, so the reveal must never be the thing that drops one.
    func testUpwardRevealNeverDropsTheSplitThatPutTheToolbarOnScreen() {
        for presentation in [BrowserSidebarPresentation.floating, .collapsed] {
            XCTAssertTrue(
                MobileBrowserRootContent.showsCompactPageToolbar(
                    sidebarPresentation: presentation,
                    presentsSplitView: true
                ),
                "A split is what puts the compact toolbar up when undocked."
            )
            XCTAssertFalse(
                MobileBrowserRootContent.showsCompactPageToolbar(
                    sidebarPresentation: presentation,
                    presentsSplitView: false
                ),
                "Without a split there is no undocked toolbar to swipe."
            )
            XCTAssertEqual(
                MobileCompactSidebarRevealDestination.destination(
                    sidebarPresentation: presentation
                ),
                .floatingSidebar,
                """
                Landing on the viewer here would drop the split and re-dock the \
                sidebar in one move — two placement changes the finger never \
                asked for.
                """
            )
        }
    }

    func testRevealingTheFloatingSidebarKeepsTheCompactPageAndItsSplitOnScreen() {
        let navigation = MobileBrowserNavigationState()
        navigation.adapt(to: .compact)
        navigation.selectTab()
        navigation.completePagePresentation()
        navigation.hideRegularSidebar()

        XCTAssertEqual(
            MobileCompactSidebarRevealDestination.destination(
                sidebarPresentation: navigation.regularSidebarPresentation
            ),
            .floatingSidebar
        )
        navigation.showRegularSidebar()

        XCTAssertEqual(navigation.regularSidebarPresentation, .floating)
        XCTAssertTrue(
            navigation.compactShowsPage,
            "The page — and the split composed on it — stays presented."
        )
    }

    func testRevealingFromADockedSidebarStillEntersTheFullScreenTabViewer() {
        let navigation = MobileBrowserNavigationState()
        navigation.adapt(to: .compact)
        navigation.selectTab()
        navigation.completePagePresentation()

        XCTAssertEqual(navigation.regularSidebarPresentation, .docked)
        XCTAssertEqual(
            MobileCompactSidebarRevealDestination.destination(
                sidebarPresentation: navigation.regularSidebarPresentation
            ),
            .tabViewer
        )
        navigation.showTabViewer()

        XCTAssertFalse(navigation.compactShowsPage)
        XCTAssertEqual(navigation.regularSidebarPresentation, .docked)
    }

    func testPageStoreRetainsTabsButNeverReusesAProfileAcrossSpaces() throws {
        let firstSpace = makeSpace(index: 1)
        let secondSpace = makeSpace(index: 2)
        let browser = BrowserStore.hostingPages(
            SessionState.Seed(spaces: [firstSpace, secondSpace]),
            showing: firstSpace.id,
            tabs: shownTabs(in: [firstSpace, secondSpace])
        )
        let pages = MobileBrowserPageStore(
            browser: browser,
            usesEphemeralWebsiteDataStores: true
        )

        pages.select()
        let firstPage = try XCTUnwrap(pages.activePage)
        XCTAssertEqual(firstPage.profileID, firstSpace.profileID)

        browser.selectSpace(secondSpace.id)
        pages.select()
        let secondPage = try XCTUnwrap(pages.activePage)
        XCTAssertEqual(secondPage.profileID, secondSpace.profileID)
        XCTAssertFalse(firstPage === secondPage)

        browser.selectSpace(firstSpace.id)
        pages.select()
        XCTAssertTrue(try XCTUnwrap(pages.activePage) === firstPage)
    }

    func testProtectionChangeReloadsOnlyThePresentedMobilePage() async throws {
        let activeTab = TabState.Seed.startPage()
        let backgroundTab = TabState.Seed.startPage()
        let space = SpaceState.Seed(name: "Protection", tabs: [activeTab, backgroundTab])
        let browser = BrowserStore.hostingPages(SessionState.Seed(spaces: [space]))
        let pages = MobileBrowserPageStore(browser: browser, usesEphemeralWebsiteDataStores: true)
        pages.present(tab: backgroundTab.id, in: space.id)
        let background = try XCTUnwrap(pages.activePage)
        pages.present(tab: activeTab.id, in: space.id)
        let active = try XCTUnwrap(pages.activePage)
        await pages.reconcileContentBlocking()
        for page in [active, background] { try await showDocument(in: page) }
        let activeCount = active.completedNavigationCount
        let backgroundCount = background.completedNavigationCount
        var preferences = try XCTUnwrap(browser.spaceModel(space.id)).settings.browsingPreferences
        preferences.contentBlocking = .off
        browser.updateBrowsingPreferences(preferences, in: space.id)
        await pages.reconcileContentBlocking()
        try await waitUntil { active.completedNavigationCount > activeCount }
        XCTAssertEqual(background.completedNavigationCount, backgroundCount)
        XCTAssertFalse(active.isContentBlockingActive)
        XCTAssertFalse(background.isContentBlockingActive)
        pages.unloadPages(in: space.id)
    }

    func testDeletingSpaceThroughMobileRegistryReleasesEveryWindowBeforeSharedData() async throws {
        let space = makeSpace(index: 35)
        let tabID = try XCTUnwrap(space.tabs.first?.id)
        let remover = RecordingMobileWebsiteDataStoreRemover()
        let primaryBrowser = BrowserStore.hostingPages(
            SessionState.Seed(spaces: [space]), core: .hostingPages(profileStores: remover))
        let primaryPages = MobileBrowserPageStore(
            browser: primaryBrowser,
            usesEphemeralWebsiteDataStores: false
        )
        // Another window of the same workspace, which keeps pages of its own.
        let secondaryPages = MobileBrowserPageStore(
            browser: primaryBrowser.makeWindowStore(),
            usesEphemeralWebsiteDataStores: true
        )
        let registry = MobileBrowserPageStoreRegistry(primary: primaryPages)
        registry.register(secondaryPages)
        primaryPages.present(space: space.id)
        secondaryPages.present(space: space.id)
        XCTAssertFalse(
            try XCTUnwrap(
                primaryPages.activePage?.webView.configuration.websiteDataStore
            ).isPersistent
        )
        XCTAssertFalse(
            try XCTUnwrap(
                secondaryPages.activePage?.webView.configuration.websiteDataStore
            ).isPersistent
        )

        try await registry.deleteData(for: BrowserSpaceRuntimeAssignment(space: space))

        XCTAssertFalse(primaryPages.containsResidentPage(for: tabID))
        XCTAssertFalse(secondaryPages.containsResidentPage(for: tabID))
        XCTAssertEqual(remover.removedProfileIDs, [space.profileID])
    }

    func testSpaceCannotRecreateItsPageWhileProfileDeletionIsSuspended() async throws {
        let deletedSpace = makeSpace(index: 33)
        let retainedSpace = makeSpace(index: 34)
        let remover = SuspendingMobileWebsiteDataStoreRemover()
        let browser = BrowserStore.hostingPages(
            SessionState.Seed(spaces: [deletedSpace, retainedSpace]), core: .hostingPages(profileStores: remover))
        let pages = MobileBrowserPageStore(
            browser: browser,
            usesEphemeralWebsiteDataStores: false
        )
        pages.present(space: deletedSpace.id)
        XCTAssertNotNil(pages.activePage)
        XCTAssertFalse(
            try XCTUnwrap(
                pages.activePage?.webView.configuration.websiteDataStore
            ).isPersistent
        )

        // Deleting the Space records the deletion before its data goes, as the app does.
        let deletion = Task {
            try await browser.deleteSpace(deletedSpace.id, dataDeleter: pages)
        }
        await remover.waitUntilRemovalStarts()

        pages.present(space: deletedSpace.id)

        XCTAssertNil(pages.activePage)
        XCTAssertEqual(pages.residentPageCount, 0)

        remover.finishRemoval()
        try await deletion.value
    }

    func testPageStoreWarningPressureKeepsOrdinaryTabsResident() async throws {
        let tabs = (1...4).map { index in
            TabState.Seed(
                id: fixedUUID(400 + index),
                title: "Tab \(index)",
                url: nil,
                symbol: "globe",
                placement: .current
            )
        }
        let space = SpaceState.Seed(
            id: fixedUUID(450),
            profileID: fixedUUID(451),
            name: "Pressure",
            folders: [],
            tabs: tabs
        )
        let browser = BrowserStore.hostingPages(
            SessionState.Seed(spaces: [space]),
            showing: space.id,
            tabs: shownTabs(in: [space], tabs: [space.id: tabs[0].id])
        )
        let pages = MobileBrowserPageStore(
            browser: browser,
            usesEphemeralWebsiteDataStores: true
        )

        for tab in tabs {
            browser.selectTab(tab.id)
            pages.select()
        }

        let activePage = try XCTUnwrap(pages.activePage)
        pages.handleMemoryPressure(.warning)

        XCTAssertEqual(pages.residentPageCount, tabs.count)
        XCTAssertTrue(pages.containsResidentPage(for: tabs[3].id))
        XCTAssertTrue(try XCTUnwrap(pages.activePage) === activePage)
        XCTAssertTrue(pages.containsResidentPage(for: tabs[0].id))
    }

    func testPageStoreCriticalPressureUnloadsOnlyTheOldestEligibleTab() async throws {
        let tabs = (1...8).map { index in
            TabState.Seed(
                id: fixedUUID(460 + index),
                title: "Tab \(index)",
                url: nil,
                symbol: "globe",
                placement: .current
            )
        }
        let space = SpaceState.Seed(
            id: fixedUUID(470),
            profileID: fixedUUID(471),
            name: "Coalescing",
            folders: [],
            tabs: tabs
        )
        let browser = BrowserStore.hostingPages(
            SessionState.Seed(spaces: [space]),
            showing: space.id,
            tabs: shownTabs(in: [space], tabs: [space.id: tabs[0].id])
        )
        let pages = MobileBrowserPageStore(
            browser: browser,
            usesEphemeralWebsiteDataStores: true
        )
        // Another window of the same workspace: its pages are relieved by the
        // same squeeze, which the core still answers once.
        let registry = MobileBrowserPageStoreRegistry(primary: pages)
        registry.register(
            MobileBrowserPageStore(browser: browser.makeWindowStore(), usesEphemeralWebsiteDataStores: true))
        let monitor = BrowserMemoryPressureMonitor(core: browser.core) { registry.liveStores }
        let squeeze = Date()

        for tab in tabs {
            browser.selectTab(tab.id)
            pages.select()
            try await showDocument(in: try XCTUnwrap(pages.activePage))
        }

        monitor.relieve(.critical, at: squeeze)

        XCTAssertEqual(pages.residentPageCount, tabs.count - 1)
        XCTAssertFalse(pages.containsResidentPage(for: tabs[0].id))
        XCTAssertTrue(pages.containsResidentPage(for: tabs[7].id))
        XCTAssertEqual(pages.activePage?.tabID, tabs[7].id)
    }

    /// A page the core closes keeping its state hands the core WebKit's
    /// history, which the tab's next page brings back in place of its first
    /// load, though nothing reaches a disk archive.
    func testAnUnloadedPageComesBackWithTheHistoryItHandedTheCore() async throws {
        let stateful = TabState.Seed(
            id: fixedUUID(520), title: "Stateful", url: nil, symbol: "globe", placement: .current)
        let other = TabState.Seed(id: fixedUUID(521), title: "Other", url: nil, symbol: "globe", placement: .current)
        let space = SpaceState.Seed(
            id: fixedUUID(522), profileID: fixedUUID(523), name: "Restore",
            folders: [], tabs: [stateful, other])
        let browser = BrowserStore.hostingPages(
            SessionState.Seed(spaces: [space]), showing: space.id,
            tabs: shownTabs(in: [space], tabs: [space.id: stateful.id]))
        let pages = MobileBrowserPageStore(browser: browser, usesEphemeralWebsiteDataStores: true)
        let firstURL = try XCTUnwrap(URL(string: "https://restore.crest.test/one"))
        let secondURL = try XCTUnwrap(URL(string: "https://restore.crest.test/two"))
        pages.select()
        let page = try XCTUnwrap(pages.activePage)
        for url in [firstURL, secondURL] {
            page.webView.loadSimulatedRequest(URLRequest(url: url), responseHTML: "<title>\(url.path)</title>")
            try await waitUntil(timeout: .seconds(5)) {
                browser.spaceModel(space.id)?.tabs.model(stateful.id)?.url == url.absoluteString
                    && !page.corePage.live.isLoading
            }
        }
        XCTAssertTrue(page.webView.canGoBack)

        browser.selectTab(other.id)
        pages.select()
        pages.unloadPage(for: stateful.id)
        XCTAssertFalse(pages.containsResidentPage(for: stateful.id))
        browser.selectTab(stateful.id)
        pages.select()
        let restored = try XCTUnwrap(pages.activePage)

        XCTAssertFalse(restored === page)
        XCTAssertEqual(restored.webView.url, secondURL)
        XCTAssertEqual(restored.webView.backForwardList.backList.map(\.url), [firstURL])
        pages.reconcile(validTabIDs: [])
    }

    /// A modified link a page stages for its Peek is spent by the first page
    /// that asks for it, never reaches a page in another website data store,
    /// never replays a body, and goes through the core, which stages it only
    /// in a page of its source's profile that has loaded nothing.
    func testAStagedLinkIsOneShotAndStaysInItsProfilesStore() throws {
        let source = makeSpace(index: 54)
        let other = makeSpace(index: 55)
        let browser = BrowserStore.hostingPages(SessionState.Seed(spaces: [source, other]))
        let url = try XCTUnwrap(URL(string: "https://example.com/next"))
        var request = URLRequest(url: url)
        request.setValue("https://example.com/source", forHTTPHeaderField: "Referer")
        func peek(in space: SpaceState.Seed) throws -> WebKitEnginePage {
            try XCTUnwrap(browser.openWebKitPage(in: space.id, for: nil)).webKit
        }
        let opened = try XCTUnwrap(browser.openWebKitPage(in: source.id, for: try XCTUnwrap(source.tabs.first).id))
        let page = opened.webKit

        let crossStore = try XCTUnwrap(page.stageLink(request))
        XCTAssertEqual(crossStore.sourcePageID, opened.core.id)
        XCTAssertFalse(try peek(in: other).stage(crossStore, expecting: url))
        XCTAssertFalse(try peek(in: source).stage(crossStore, expecting: url), "A refused link is spent.")

        let link = try XCTUnwrap(page.stageLink(request))
        XCTAssertTrue(try peek(in: source).stage(link, expecting: url))
        XCTAssertFalse(try peek(in: source).stage(link, expecting: url))

        var post = request
        post.httpMethod = "POST"
        XCTAssertNil(page.stageLink(post))
    }

    /// Media starting in a WebKit page reaches the page's host, which asks
    /// WebKit what the page runs and tells the core, so memory pressure never
    /// decides on media the core has not heard of.
    func testMediaStartingInAPageTellsItsHost() async throws {
        let space = makeSpace(index: 53)
        let tab = try XCTUnwrap(space.tabs.first)
        let browser = BrowserStore.hostingPages(SessionState.Seed(spaces: [space]))
        let opened = try XCTUnwrap(browser.openWebKitPage(in: space.id, for: tab.id))
        defer { opened.core.release(keepingState: false) }
        let host = MediaActivityHost()
        opened.webKit.attach(host)
        let webView = opened.webKit.webView
        webView.loadSimulatedRequest(
            URLRequest(url: try XCTUnwrap(URL(string: "https://media.crest.test/"))), responseHTML: "<p>Media</p>")
        try await waitUntil(timeout: .seconds(5)) { webView.url != nil && !webView.isLoading }

        _ = try await webView.evaluateJavaScript("document.dispatchEvent(new Event('play')); true")
        try await waitUntil(timeout: .seconds(5)) { host.mediaChanges > 0 }
    }

    /// Has `page` show a document of its own, which the core then holds,
    /// since memory pressure never unloads a page that showed none.
    private func showDocument(in page: MobileBrowserPage) async throws {
        let url = try XCTUnwrap(URL(string: "https://pressure.crest.test/\(page.tabID.uuidString)"))
        page.webView.loadSimulatedRequest(URLRequest(url: url), responseHTML: "<p>Resident</p>")
        try await waitUntil(timeout: .seconds(5)) { page.corePage.live.url != nil && !page.corePage.live.isLoading }
    }

    private func waitUntil(
        timeout: Duration = .seconds(3),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            guard clock.now < deadline else {
                XCTFail("Timed out waiting for the browser state to change.")
                return
            }
            try await Task.sleep(for: .milliseconds(25))
        }
    }

    private func makeSpace(index: Int) -> SpaceState.Seed {
        let tab = TabState.Seed.startPage(
            id: fixedUUID(index * 10 + 1),
            placement: .current
        )
        return SpaceState.Seed(
            id: fixedUUID(index * 10 + 2),
            profileID: fixedUUID(index * 10 + 3),
            name: "Space \(index)",
            folders: [],
            tabs: [tab]
        )
    }

    /// The tab a window shows in each of `spaces`: the one `tabs` names for
    /// it, or else its first tab.
    private func shownTabs(in spaces: [SpaceState.Seed], tabs: [UUID: UUID] = [:]) -> [UUID: UUID] {
        var shown: [UUID: UUID] = [:]
        for space in spaces {
            shown[space.id] = tabs[space.id] ?? space.tabs.first?.id
        }
        return shown
    }

    private func fixedUUID(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", value))!
    }

    /// Hosts a compact browser surface in a window whose safe area stands in for
    /// a notched iPhone, laid out far enough to attach its web views.
    private func mountBrowserSurface(
        safeAreaInsets: UIEdgeInsets,
        content: some View
    ) -> UIWindow {
        let controller = UIHostingController(rootView: content)
        controller.additionalSafeAreaInsets = safeAreaInsets
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = controller
        window.isHidden = false
        window.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        window.layoutIfNeeded()
        return window
    }

    private func firstWebHostView(in view: UIView) -> MobileBrowserWebHostView? {
        if let host = view as? MobileBrowserWebHostView { return host }
        for subview in view.subviews {
            if let host = firstWebHostView(in: subview) { return host }
        }
        return nil
    }
}

@MainActor
private final class RecordingMobileWebsiteDataStoreRemover:
    BrowserEngineProfileRemoving
{
    private(set) var removedProfileIDs: [UUID] = []

    func removeProfile(_ profile: BrowsingProfile, ephemeral: Bool) async throws {
        removedProfileIDs.append(profile.id)
    }
}

/// A WebKit page's host that counts how often the page said its media may
/// have changed.
@MainActor
private final class MediaActivityHost: WebKitPageHosting {
    private(set) var mediaChanges = 0

    func ask(_ asked: ScriptDialogAsked, dismissal: BrowserPromptDismissal) {}

    func ask(_ asked: AuthenticationAsked, dismissal: BrowserPromptDismissal) {}

    func ask(_ asked: PermissionAsked, dismissal: BrowserPromptDismissal) {}

    func prepareToLoad(_ url: URL) {}

    func mediaActivityMayHaveChanged() {
        mediaChanges += 1
    }

    func historyMayHaveChanged() {}
}
