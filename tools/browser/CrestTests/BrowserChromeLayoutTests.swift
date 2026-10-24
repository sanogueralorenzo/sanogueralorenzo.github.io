import AppKit
import SwiftUI
import WebKit
import XCTest

@testable import Crest

final class BrowserChromeLayoutTests: XCTestCase {

    @MainActor
    func testSettingsPresentationKeepsTheLatestDestinationAndSpace() {
        let presentation = BrowserSpaceSettingsPresentationState()
        let first = UUID()
        let second = UUID()
        let firstAssignment = BrowserSpaceRuntimeAssignment(
            spaceID: first,
            profileID: UUID()
        )
        let secondAssignment = BrowserSpaceRuntimeAssignment(
            spaceID: second,
            profileID: UUID()
        )

        presentation.present(assignment: firstAssignment)
        presentation.present(.shortcuts, assignment: secondAssignment)

        XCTAssertEqual(presentation.requestedSpaceID, second)
        XCTAssertEqual(presentation.requestedAssignment, secondAssignment)
        XCTAssertEqual((presentation.request as? BrowserSettingsDestinationRequest)?.destination, .shortcuts)
        XCTAssertEqual(presentation.revision, 2)
    }

    @MainActor
    func testRepeatedSettingsPresentationStillPublishesANewRequest() {
        let presentation = BrowserSpaceSettingsPresentationState()
        let spaceID = UUID()
        let assignment = BrowserSpaceRuntimeAssignment(
            spaceID: spaceID,
            profileID: UUID()
        )

        presentation.present(.shortcuts, assignment: assignment)
        presentation.present(.shortcuts, assignment: assignment)

        XCTAssertEqual((presentation.request as? BrowserSettingsDestinationRequest)?.destination, .shortcuts)
        XCTAssertEqual(presentation.requestedSpaceID, spaceID)
        XCTAssertEqual(presentation.revision, 2)
    }

    @MainActor
    func testSettingsPresentationRejectsAReplacementBrowsingProfile() throws {
        let browser = BrowserStore(seed: .preview)
        let original = try XCTUnwrap(browser.shownSpace)
        let presentation = BrowserSpaceSettingsPresentationState()
        presentation.present(
            assignment: BrowserSpaceRuntimeAssignment(space: original)
        )
        browser.replaceProfileForTesting(of: original.id)

        XCTAssertNil(presentation.requestedSpaceID(in: browser))
    }

    func testCertificateReviewRequiresHTTPSAndServerTrust() {
        XCTAssertTrue(
            BrowserPage.canReviewCertificate(
                of: URL(string: "https://example.com"),
                hasServerTrust: true
            )
        )
        XCTAssertFalse(
            BrowserPage.canReviewCertificate(
                of: URL(string: "http://example.com"),
                hasServerTrust: true
            )
        )
        XCTAssertFalse(
            BrowserPage.canReviewCertificate(
                of: URL(string: "https://example.com"),
                hasServerTrust: false
            )
        )
    }

    @MainActor
    func testSidebarClearHistoryKeepsTheInitiatingSpaceAfterSelectionChanges() throws {
        let browser = BrowserStore(seed: .preview)
        let initiatingSpace = try XCTUnwrap(browser.shownSpace)
        let laterSelectedSpace = try XCTUnwrap(
            browser.spaceModels.first { $0.id != initiatingSpace.id }
        )
        let clearHistory = BrowserSidebarClearHistoryConfirmation(
            assignment: BrowserSpaceRuntimeAssignment(space: initiatingSpace),
            spaceName: initiatingSpace.settings.name
        )

        browser.selectSpace(laterSelectedSpace.id)

        XCTAssertEqual(browser.selectedSpaceID, laterSelectedSpace.id)
        XCTAssertEqual(clearHistory.spaceID, initiatingSpace.id)
        XCTAssertEqual(clearHistory.spaceName, initiatingSpace.settings.name)
    }

    @MainActor
    func testWindowAccessibilityNamesAWindowThatDrawsItsOwnChrome() {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        BrowserWindowAccessibility.pinTitle(
            BrowserOnboardingWindowActivation.windowTitle,
            on: window
        )

        XCTAssertTrue(
            window.styleMask.contains(.titled),
            "A borderless window carries no title, so it cannot be addressed by name."
        )
        XCTAssertEqual(window.title, "Crest Setup")
        XCTAssertEqual(window.accessibilityTitle(), "Crest Setup")
    }

    func testPeekKeyboardDismissalLeavesReturnToThePage() {
        XCTAssertTrue(
            BrowserPeekKeyboardMonitorCoordinator.dismisses(keyCode: 53, modifierFlags: [])
        )
        XCTAssertFalse(
            BrowserPeekKeyboardMonitorCoordinator.dismisses(keyCode: 36, modifierFlags: [])
        )
        XCTAssertFalse(
            BrowserPeekKeyboardMonitorCoordinator.dismisses(keyCode: 76, modifierFlags: [])
        )
        XCTAssertFalse(
            BrowserPeekKeyboardMonitorCoordinator.dismisses(
                keyCode: 36,
                modifierFlags: [.command]
            )
        )
    }

    func testChromeAccessibilityValuesPreserveTabFolderAndBadgeState() {
        XCTAssertEqual(
            BrowserChromeAccessibility.tabValue(isLoaded: true),
            "Loaded"
        )
        XCTAssertEqual(
            BrowserChromeAccessibility.tabValue(isLoaded: false),
            "Not loaded"
        )
        XCTAssertEqual(
            BrowserChromeAccessibility.folderValue(isExpanded: true),
            "Expanded"
        )
        XCTAssertEqual(
            BrowserChromeAccessibility.folderValue(isExpanded: false),
            "Collapsed"
        )
        XCTAssertEqual(
            BrowserChromeAccessibility.countValue(
                1,
                singular: "download",
                plural: "downloads"
            ),
            "1 download"
        )
        XCTAssertEqual(
            BrowserChromeAccessibility.countValue(
                2,
                singular: "archived tab",
                plural: "archived tabs"
            ),
            "2 archived tabs"
        )
    }

    func testSidebarResizeKeepsIntermediateWidthsInMemoryUntilCommit() {
        var transaction = BrowserSidebarWidthTransaction(persistedWidth: 289)

        transaction.resize(to: 302)
        transaction.resize(to: 318)
        transaction.resize(to: 341)

        XCTAssertEqual(transaction.width, 341)
        XCTAssertEqual(transaction.persistedWidth, 289)
        XCTAssertEqual(transaction.commit(), 341)
        XCTAssertEqual(transaction.persistedWidth, 341)
        XCTAssertNil(transaction.commit())
    }

    /// A pointer that reveals the floating sidebar from the window edge can
    /// leave the window before the card slides under it. That still counts as
    /// leaving, or the sidebar stays out until the pointer returns to it, and
    /// each new reveal reports it again. A sidebar opened any other way waits
    /// for the pointer to arrive first.
    @MainActor
    func testSidebarRevealedByThePointerHidesWhenThePointerLeavesBeforeArriving() {
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 800, height: 600),
            styleMask: [.titled], backing: .buffered, defer: true
        )
        var reports: [Bool] = []
        let tracker = BrowserSidebarHoverTrackingView(
            notificationCenter: NotificationCenter(),
            pointerLocation: { NSPoint(x: 40, y: 300) },
            onHoverChange: { reports.append($0) }
        )
        tracker.frame = NSRect(x: 0, y: 0, width: 300, height: 600)
        window.contentView?.addSubview(tracker)

        tracker.refreshPointerHover()
        XCTAssertEqual(reports, [])

        tracker.isRevealedByPointer = true
        tracker.refreshPointerHover()
        XCTAssertEqual(reports, [false])

        // The pointer touches the edge again before the region is taken down.
        tracker.isRevealedByPointer = false
        tracker.isRevealedByPointer = true
        tracker.refreshPointerHover()
        XCTAssertEqual(reports, [false, false])
    }

    /// The edge strip reappears under a pointer that is still resting where
    /// the sidebar just hid, as Universal Control leaves it after crossing to
    /// another Mac. Only a pointer that moves onto the strip reveals it again.
    @MainActor
    func testCollapsedSidebarEdgeRevealsOnlyForAPointerThatMoves() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled], backing: .buffered, defer: true
        )
        var pointer = NSPoint(x: 0, y: 300)
        var reports: [Bool] = []
        let edge = BrowserCollapsedSidebarHoverTrackingView(
            pointerLocation: { pointer },
            onHoverChange: { reports.append($0) }
        )
        edge.frame = NSRect(x: 0, y: 0, width: 6, height: 600)
        window.contentView?.addSubview(edge)
        let event = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .mouseMoved, location: pointer, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0
            )
        )

        edge.mouseEntered(with: event)
        edge.mouseMoved(with: event)
        XCTAssertEqual(reports, [])

        pointer.y += 1
        edge.mouseMoved(with: event)
        XCTAssertEqual(reports, [true])
    }

    func testSidebarAuxiliaryMouseButtonsSwitchSpacesWithoutClaimingOtherButtons() {
        XCTAssertEqual(
            BrowserSidebarMouseButtonAction(buttonNumber: 3),
            .previousSpace
        )
        XCTAssertEqual(
            BrowserSidebarMouseButtonAction(buttonNumber: 4),
            .nextSpace
        )
        XCTAssertNil(BrowserSidebarMouseButtonAction(buttonNumber: 0))
        XCTAssertNil(BrowserSidebarMouseButtonAction(buttonNumber: 1))
        XCTAssertNil(BrowserSidebarMouseButtonAction(buttonNumber: 2))
        XCTAssertNil(BrowserSidebarMouseButtonAction(buttonNumber: 5))
    }

    func testAuxiliaryMouseButtonsStayWithinWebpageScope() {
        for action in [
            BrowserSidebarMouseButtonAction.previousSpace,
            .nextSpace,
        ] {
            XCTAssertEqual(
                BrowserSidebarMousePointerScope.webpage.disposition(
                    for: action,
                    canNavigatePage: true
                ),
                .navigatePage(action)
            )
            XCTAssertEqual(
                BrowserSidebarMousePointerScope.webpage.disposition(
                    for: action,
                    canNavigatePage: false
                ),
                .consume
            )
        }
    }

    func testAuxiliaryMouseButtonsStayWithinSidebarScope() {
        for action in [
            BrowserSidebarMouseButtonAction.previousSpace,
            .nextSpace,
        ] {
            XCTAssertEqual(
                BrowserSidebarMousePointerScope.sidebar.disposition(
                    for: action,
                    canNavigatePage: true
                ),
                .switchSpace(action)
            )
            XCTAssertEqual(
                BrowserSidebarMousePointerScope.sidebar.disposition(
                    for: action,
                    canNavigatePage: false
                ),
                .switchSpace(action)
            )
        }
    }

    /// A swipe no page took, such as a mouse's Back action over a Chromium
    /// page, moves the way WebKit's views and Chrome's windows move it.
    func testUnhandledSwipeGoesBackOnAPositiveDeltaAsTheEnginesDo() {
        XCTAssertEqual(BrowserSidebarMouseButtonAction(swipeDeltaX: 1), .previousSpace)
        XCTAssertEqual(BrowserSidebarMouseButtonAction(swipeDeltaX: -1), .nextSpace)
        XCTAssertNil(BrowserSidebarMouseButtonAction(swipeDeltaX: 0))
    }

    func testAuxiliaryMouseButtonsRemainUnclaimedOutsidePageAndSidebar() {
        for action in [
            BrowserSidebarMouseButtonAction.previousSpace,
            .nextSpace,
        ] {
            XCTAssertNil(
                BrowserSidebarMousePointerScope.unowned.disposition(
                    for: action,
                    canNavigatePage: true
                )
            )
        }
    }

    @MainActor
    func testOpenLocationPreservesSidebarStateAndPresentsTheCommandSurface() {
        for sidebarIsPresented in [false, true] {
            let chrome = BrowserChromeState(sidebarIsPresented: sidebarIsPresented)
            let visibility = chrome.columnVisibility

            chrome.openLocation("https://example.com")

            XCTAssertEqual(chrome.columnVisibility, visibility)
            XCTAssertEqual(
                chrome.commandPaletteMode,
                .editLocation("https://example.com")
            )
            chrome.dismissCommandPalette()
            XCTAssertEqual(chrome.columnVisibility, visibility)
        }
    }

    @MainActor
    func testRepeatedOpenLocationRequestsReplaceThePaletteQuery() {
        let chrome = BrowserChromeState()

        chrome.openLocation("https://example.com")
        chrome.openLocation("https://webkit.org")

        XCTAssertEqual(
            chrome.commandPaletteMode,
            .editLocation("https://webkit.org")
        )
    }

    @MainActor
    func testArchiveAndDownloadsPresentationIsExclusiveToItsOwningWindow() {
        let firstWindow = BrowserChromeState()
        let secondWindow = BrowserChromeState()

        firstWindow.utilityPresentation.present(.downloads)

        XCTAssertEqual(firstWindow.utilityPresentation.surface, .downloads)
        XCTAssertNil(secondWindow.utilityPresentation.surface)

        firstWindow.utilityPresentation.present(.archive)

        XCTAssertEqual(firstWindow.utilityPresentation.surface, .archive)
        XCTAssertNil(secondWindow.utilityPresentation.surface)

        firstWindow.utilityPresentation.dismiss(.downloads)
        XCTAssertEqual(
            firstWindow.utilityPresentation.surface,
            .archive,
            "A stale popover dismissal must not close the replacement Archive surface."
        )

        firstWindow.utilityPresentation.dismiss(.archive)
        XCTAssertNil(firstWindow.utilityPresentation.surface)
    }

    /// Commands reveal their list without overriding the owning window's docked-sidebar preference.
    @MainActor
    func testShowListCommandsBringTheirListOnScreen() {
        let browser = BrowserStore.hostingPages()
        let pages = BrowserPagePool(browser: browser)
        let lists: [(ShortcutCommand, BrowserUtilitySurface)] = [
            (.showHistory, .history), (.showArchive, .archive), (.showDownloads, .downloads),
        ]

        for (command, surface) in lists {
            let hidden = BrowserChromeState(sidebarIsPresented: false)
            BrowserCommandActions(browser: browser, pages: pages, chrome: hidden, windows: nil).perform(command)
            XCTAssertEqual(
                hidden.columnVisibility, .detailOnly, "\(command.name) preserves the hidden sidebar preference.")
            XCTAssertTrue(hidden.isFloatingSidebarPresented)
            XCTAssertEqual(hidden.utilityPresentation.surface, surface)

            let floating = BrowserChromeState(sidebarIsPresented: false)
            floating.isFloatingSidebarPresented = true
            BrowserCommandActions(browser: browser, pages: pages, chrome: floating, windows: nil).perform(command)
            XCTAssertEqual(floating.columnVisibility, .detailOnly, "\(command.name) keeps a floating sidebar.")
            XCTAssertEqual(floating.utilityPresentation.surface, surface)
        }
    }

    @MainActor
    func testMacChromeRestoresItsOwningWindowsSidebarPresentation() {
        let hiddenChrome = BrowserChromeState(sidebarIsPresented: false)
        let visibleChrome = BrowserChromeState(sidebarIsPresented: true)

        XCTAssertEqual(hiddenChrome.columnVisibility, .detailOnly)
        XCTAssertEqual(visibleChrome.columnVisibility, .all)
    }

}

extension BrowserChromeLayoutTests {
    @MainActor
    func testChromePreferencesPersistOnlyInTheirNamedIsolationDomain() {
        let id = "chrome-test-\(UUID().uuidString)"
        let environment = BrowserLaunchEnvironment(
            values: ["CREST_ISOLATED_SESSION": "1", "CREST_ISOLATED_PERSISTENCE_ID": id],
            isXCTestRuntime: false
        )
        let defaults = BrowserChromeAppearancePreference.defaults(for: environment)
        defer {
            defaults.removePersistentDomain(
                forName: BrowserLaunchEnvironment.isolatedDefaultsSuiteName(isolationID: id))
        }
        XCTAssertFalse(defaults.bool(forKey: BrowserChromeAppearancePreference.sidebarOnRightKey))
        XCTAssertFalse(defaults.bool(forKey: BrowserChromeAppearancePreference.borderlessKey))
        defaults.set(true, forKey: BrowserChromeAppearancePreference.sidebarOnRightKey)
        defaults.set(true, forKey: BrowserChromeAppearancePreference.borderlessKey)
        let restored = BrowserChromeAppearancePreference.defaults(for: environment)
        XCTAssertTrue(restored.bool(forKey: BrowserChromeAppearancePreference.sidebarOnRightKey))
        XCTAssertTrue(restored.bool(forKey: BrowserChromeAppearancePreference.borderlessKey))
        XCTAssertFalse(restored === UserDefaults.standard)
    }

    @MainActor
    func testWindowBorderMigratesAndKeepsDeviceLocalWidth() {
        let suite = "window-border-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        for (legacyBorderless, expectedWidth) in [(true, 0.0), (false, 8.0)] {
            defaults.removeObject(forKey: BrowserChromeAppearancePreference.borderWidthKey)
            defaults.set(legacyBorderless, forKey: BrowserChromeAppearancePreference.borderlessKey)
            BrowserChromeAppearancePreference.migrateBorderWidth(in: defaults)
            XCTAssertEqual(defaults.double(forKey: BrowserChromeAppearancePreference.borderWidthKey), expectedWidth)
        }
        defaults.set(3.5, forKey: BrowserChromeAppearancePreference.borderWidthKey)
        defaults.set(true, forKey: BrowserChromeAppearancePreference.borderlessKey)
        BrowserChromeAppearancePreference.migrateBorderWidth(in: defaults)
        XCTAssertEqual(
            UserDefaults(suiteName: suite)!.double(forKey: BrowserChromeAppearancePreference.borderWidthKey), 3.5)

    }

    @MainActor
    func testChromeAppearanceChangesPreserveLivePageHostsAndDocumentState() async throws {
        for split in [false, true] {
            var space = BrowserRootPreviewFixture.space
            let members = BrowserRootPreviewFixture.splitMembers
            space.tabs = split ? members : [members[0]]
            for index in space.tabs.indices {
                space.tabs[index].url = "about:blank"
                if !split { space.tabs[index].splitGroupID = nil }
            }
            let selectedTabID = space.tabs[0].id
            let browser = BrowserStore.hostingPages(
                SessionState.Seed(spaces: [space]),
                showing: space.id, tabs: [space.id: selectedTabID])
            let pages = BrowserPagePool(browser: browser)
            pages.select()
            let model = BrowserRootModel(
                browser: browser, pages: pages, chrome: BrowserChromeState(sidebarIsPresented: true),
                spaceAccess: BrowserSpaceAccessController(), windowState: nil, startupBehavior: .showStartPage,
                persistedSidebarWidth: 289)
            let spaceModel = try XCTUnwrap(browser.spaceModel(space.id))
            let livePages = try space.tabs.map { tab in
                try XCTUnwrap(pages.surfacePage(for: tab.id, in: spaceModel, accessController: model.spaceAccess))
            }
            // Finish the pool's initial blank documents before starting this
            // navigation, so their late completion cannot contaminate the baseline.
            for _ in 0..<100 {
                if livePages.allSatisfy({ !$0.webView.isLoading && $0.completedNavigationCount > 0 }) { break }
                try await Task.sleep(for: .milliseconds(20))
            }
            let initialCounts = livePages.map(\.completedNavigationCount)
            for page in livePages {
                page.setDeveloperToolbarVisible(true)
                page.webView.loadHTMLString(
                    "<body style='height:4000px'><input id='draft'><script>window.chromeIdentity=Math.random().toString(36);</script></body>",
                    baseURL: nil)
            }
            for _ in 0..<100 {
                if livePages.enumerated().allSatisfy({
                    !$0.element.webView.isLoading && $0.element.completedNavigationCount > initialCounts[$0.offset]
                }) {
                    break
                }
                try await Task.sleep(for: .milliseconds(20))
            }
            let host = NSHostingView(rootView: ChromeContinuityTestShell(model: model))
            let window = NSWindow(
                contentRect: CGRect(x: 0, y: 0, width: 1200, height: 800), styleMask: [.titled, .closable, .resizable],
                backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.orderFront(nil)
            defer { window.close() }
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(80))
            let parents = try livePages.map { try XCTUnwrap($0.webView.superview) }
            let navigationCounts = livePages.map(\.completedNavigationCount)
            var documentIDs: [String] = []
            for page in livePages {
                let identifier = try await page.webView.evaluateJavaScript(
                    "document.querySelector('#draft').value='unsaved';window.scrollTo(0,300);window.chromeIdentity")
                documentIDs.append(try XCTUnwrap(identifier as? String))
            }
            for appearance in [
                BrowserChromeAppearance(sidebarOnRight: true, borderless: true),
                .init(sidebarOnRight: false, borderless: true), .init(sidebarOnRight: true, borderless: false), .init(),
            ] {
                host.rootView = ChromeContinuityTestShell(model: model, appearance: appearance)
                host.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(300))
                XCTAssertEqual(browser.selectedSpaceID, space.id)
                XCTAssertEqual(browser.shownTab?.id, selectedTabID)
                for (index, page) in livePages.enumerated() {
                    XCTAssertTrue(
                        page.webView.superview === parents[index], "A chrome change must not detach the live web view")
                    XCTAssertEqual(page.completedNavigationCount, navigationCounts[index])
                    let value =
                        try await page.webView.evaluateJavaScript(
                            "[window.chromeIdentity,document.querySelector('#draft').value,Math.round(scrollY)]")
                        as? [Any]
                    XCTAssertEqual(value?[0] as? String, documentIDs[index])
                    XCTAssertEqual(value?[1] as? String, "unsaved")
                    XCTAssertEqual(value?[2] as? Int, 300)
                }
            }
            if split {
                host.rootView = ChromeContinuityTestShell(
                    model: model, appearance: .init(sidebarOnRight: true, borderless: true))
                window.setContentSize(NSSize(width: 1000, height: 800))
                model.splitWidthTransactionBinding.wrappedValue = BrowserSplitWidthTransaction(
                    persistedFractions: [0.8, 0.2])
                for focusedIndex in [1, 0, 1] {
                    model.focusSplitCard(space.tabs[focusedIndex].id)
                    pages.select()
                    host.layoutSubtreeIfNeeded()
                    try await Task.sleep(for: .milliseconds(300))
                    for (index, livePage) in livePages.enumerated() {
                        XCTAssertTrue(livePage.webView.superview === parents[index])
                        XCTAssertEqual(livePage.completedNavigationCount, navigationCounts[index])
                    }
                }
            }
        }
    }
}

private struct ChromeContinuityTestShell: View {
    let model: BrowserRootModel
    var appearance = BrowserChromeAppearance()
    @Namespace private var commandNamespace
    @Namespace private var tabNamespace
    var body: some View {
        BrowserRootShell(
            model: model, transientBrowsing: BrowserTransientBrowsingCoordinator(),
            spaceSettingsPresentation: BrowserSpaceSettingsPresentationState(), shortcuts: nil,
            storedSidebarWidth: .constant(289), appearance: appearance,
            commandSurfaceNamespace: commandNamespace, tabPromotionNamespace: tabNamespace
        )
        .environment(model.sidebarInteraction)
    }
}
