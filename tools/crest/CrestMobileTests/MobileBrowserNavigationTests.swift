import SwiftUI
import UIKit
import WebKit
import XCTest

@testable import CrestMobile

@MainActor
final class MobileBrowserNavigationTests: XCTestCase {

    func testLockedCompactDetailNeverAutomaticallyRestoresItsPage() throws {
        var locked = makeSpace(index: 195)
        let tab = TabState.Seed(title: "Protected", url: URL(string: "about:blank"), placement: .current)
        locked.tabs = [tab]
        locked.settings.accessPolicy = .deviceOwnerAuthentication
        let browser = BrowserStore.hostingPages(
            SessionState.Seed(spaces: [locked]),
            showing: locked.id,
            tabs: shownTabs(in: [locked])
        )
        let pages = MobileBrowserPageStore(browser: browser, usesEphemeralWebsiteDataStores: true)
        let access = BrowserSpaceAccessController()
        let detail = MobileBrowserDetailView(
            browser: browser, pages: pages, spaceAccess: access,
            address: .constant(""), isAddressEditing: .constant(false),
            addressFocusRequest: 0, isCommandPalettePresented: false,
            isCompact: true, obscuresSystemSafeAreas: false,
            showsCompactToolbar: false, compactToolbarIsHidden: false,
            handleWebContentInteraction: {}, submitAddress: {}, beginNewTab: {},
            showTabViewer: {}, hideCompactToolbar: {}, showCompactToolbar: {},
            showSwipedTab: { _ in },
            compactTransitionEnded: { _ in }
        )
        let window = mountBrowserSurface(safeAreaInsets: .zero, content: detail)
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        XCTAssertNil(pages.activePage)
        XCTAssertFalse(pages.containsResidentPage(for: tab.id))

        // The same mounted detail must still restore an authorized tab, once
        // the person authenticated to take the protection away.
        browser.unlockForTesting(locked)
        browser.updateSpaceAccessPolicy(.open, in: locked.id)
        window.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(pages.activePage?.tabID, tab.id)

        browser.updateSpaceAccessPolicy(.deviceOwnerAuthentication, in: locked.id)
        pages.relockProtectedSpace(try XCTUnwrap(browser.shownSpace))
        window.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        XCTAssertNil(pages.activePage)
        XCTAssertTrue(pages.containsResidentPage(for: tab.id))
        XCTAssertNil(firstWebHostView(in: window))
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

    // MARK: - Upward reveal routing

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
            symbol: "memorychip",
            accent: .teal,
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
            symbol: "circle",
            accent: .indigo,
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
