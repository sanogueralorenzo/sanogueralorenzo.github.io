import AppKit
import XCTest

@testable import Crest

@MainActor
final class BrowserMacWindowCoordinatorTests: XCTestCase {
    func testQuickWindowPromotionReusesAHiddenWindowAndRevealsThePromotedTab() throws {
        let fixture = makeFixture()
        let destination = try XCTUnwrap(fixture.coordinator.model(for: .initial))
        let window = makeNativeWindow()
        defer {
            fixture.coordinator.closeWindow(destination.id)
            window.close()
        }
        XCTAssertTrue(fixture.coordinator.attach(window, to: destination.id))
        let previousTabID = destination.browser.shownTab?.id
        let promotedTabID = try XCTUnwrap(fixture.browser.openNewTab(url: URL(string: "about:blank")!))
        XCTAssertEqual(destination.browser.shownTab?.id, previousTabID)
        XCTAssertFalse(window.isVisible)

        XCTAssertTrue(fixture.coordinator.activateExistingWindow(for: fixture.browser))

        XCTAssertEqual(destination.browser.shownTab?.id, promotedTabID)
        XCTAssertTrue(window.isVisible)
        XCTAssertNotNil(destination.pages.activePage)
    }

    func testQuickWindowPromotionPrefersItsOwningWindowAndFallsBackAfterItCloses() throws {
        let fixture = makeFixture()
        let source = try XCTUnwrap(fixture.coordinator.model(for: .initial))
        let other = try XCTUnwrap(fixture.coordinator.model(for: .normal(sourceWindowID: source.id)))
        let sourceWindow = makeNativeWindow()
        let otherWindow = makeNativeWindow()
        defer {
            fixture.coordinator.closeWindow(source.id)
            fixture.coordinator.closeWindow(other.id)
            sourceWindow.close()
            otherWindow.close()
        }
        XCTAssertTrue(fixture.coordinator.attach(sourceWindow, to: source.id))
        XCTAssertTrue(fixture.coordinator.attach(otherWindow, to: other.id))
        let otherTabID = other.browser.shownTab?.id
        let promotedTabID = try XCTUnwrap(source.browser.openNewTab(url: URL(string: "about:blank")!))

        XCTAssertTrue(fixture.coordinator.activateExistingWindow(for: source.browser))
        XCTAssertEqual(other.browser.shownTab?.id, otherTabID)
        XCTAssertTrue(sourceWindow.isVisible)
        XCTAssertFalse(otherWindow.isVisible)

        fixture.coordinator.closeWindow(source.id)
        sourceWindow.close()
        XCTAssertTrue(fixture.coordinator.activateExistingWindow(for: source.browser))
        XCTAssertEqual(other.browser.shownTab?.id, promotedTabID)
        XCTAssertTrue(otherWindow.isVisible)

        fixture.coordinator.closeWindow(other.id)
        otherWindow.close()
        XCTAssertFalse(fixture.coordinator.activateExistingWindow(for: source.browser))
    }

    func testQuickWindowPromotionDoesNotUseATemporaryWindowForTheSharedWorkspace() throws {
        let fixture = makeFixture()
        let source = try XCTUnwrap(fixture.coordinator.model(for: .initial))
        XCTAssertFalse(fixture.coordinator.activateExistingWindow(for: source.browser))
        let space = try XCTUnwrap(source.browser.shownSpace)
        let temporary = try XCTUnwrap(
            fixture.coordinator.model(
                for: .temporary(
                    sourceWindowID: source.id, assignment: BrowserSpaceRuntimeAssignment(space: space))))
        let window = makeNativeWindow()
        defer {
            fixture.coordinator.closeWindow(temporary.id)
            fixture.coordinator.closeWindow(source.id)
            window.close()
        }
        XCTAssertTrue(fixture.coordinator.attach(window, to: temporary.id))

        XCTAssertFalse(fixture.coordinator.activateExistingWindow(for: source.browser))
        XCTAssertFalse(window.isVisible)
        XCTAssertFalse(fixture.coordinator.activateExistingWindow(for: temporary.browser))
        XCTAssertFalse(window.isVisible)

        let primaryPages = BrowserPagePool(browser: fixture.browser.makeWindowStore())
        let registry = BrowserPagePoolRegistry(primary: primaryPages)
        registry.register(temporary.pages, browser: temporary.browser, for: temporary.id)
        let context = try XCTUnwrap(
            BrowserQuickWindowBrowsingContext(
                targetWindowID: temporary.id, browser: fixture.browser, pages: primaryPages,
                pagePoolRegistry: registry))
        XCTAssertTrue(context.browser === fixture.browser)
        XCTAssertTrue(context.pages === primaryPages)
        XCTAssertFalse(context.supportsLivePagePromotion)
    }

    func testTearOffWaitsForDestinationAndMovesTheLivePageWithoutClosingSourceWindow() throws {
        let fixture = makeFixture()
        let source = try XCTUnwrap(fixture.coordinator.model(for: .initial))
        let tab = try XCTUnwrap(source.browser.shownTab)
        let space = try XCTUnwrap(source.browser.shownSpace)
        source.pages.select()
        let page = try XCTUnwrap(source.pages.activePage)
        let request = try XCTUnwrap(
            fixture.coordinator.prepareTearOff(
                BrowserTabDragItem(tabID: tab.id, spaceID: space.id, profileID: space.profileID),
                from: source.id))

        XCTAssertNotNil(source.browser.spaceModel(space.id)?.tabs.models.first { $0.id == tab.id })
        let destination = try XCTUnwrap(fixture.coordinator.model(for: request))
        XCTAssertTrue(destination.browser.spaceModels.allSatisfy { $0.tabs.models.isEmpty })

        XCTAssertTrue(fixture.coordinator.completePendingTransfer(to: destination.id))

        XCTAssertTrue(destination.pages.activePage === page)
        XCTAssertEqual(destination.browser.shownTab?.id, tab.id)
        XCTAssertTrue(destination.browser.isTemporaryWorkspace)
        XCTAssertFalse(destination.browser.syncsSession)
        XCTAssertFalse(source.browser.spaceModel(space.id)?.tabs.contains(tab.id) ?? true)
        XCTAssertNotNil(fixture.coordinator.existingModel(for: source.id))
        XCTAssertTrue(source.browser.shownSpace?.archive.entries.isEmpty == true)

        // Closing the window closes its workspace, and a scene that asks for
        // the window again while SwiftUI tears it down opens nothing.
        let workspace = destination.browser.family
        fixture.coordinator.closeWindow(destination.id)
        XCTAssertFalse(workspace.isOpen)
        XCTAssertNil(fixture.coordinator.model(for: request))
    }

    func testCanceledOrStaleTearOffLeavesTheSourceUntouched() throws {
        let fixture = makeFixture()
        let source = try XCTUnwrap(fixture.coordinator.model(for: .initial))
        let tab = try XCTUnwrap(source.browser.shownTab)
        let space = try XCTUnwrap(source.browser.shownSpace)
        let item = BrowserTabDragItem(tabID: tab.id, spaceID: space.id, profileID: space.profileID)
        let request = try XCTUnwrap(fixture.coordinator.prepareTearOff(item, from: source.id))
        let canceled = try XCTUnwrap(fixture.coordinator.existingModel(for: request.id)).browser.family
        fixture.coordinator.cancelPendingTransfer(to: request.id)

        // The canceled window's workspace closes with it.
        XCTAssertFalse(canceled.isOpen)
        XCTAssertNil(fixture.browser.core.state.workspaces[canceled.workspaceID])
        XCTAssertFalse(fixture.coordinator.completePendingTransfer(to: request.id))
        XCTAssertEqual(source.browser.shownTab?.id, tab.id)
        XCTAssertNil(fixture.coordinator.existingModel(for: request.id))
        XCTAssertNil(fixture.coordinator.model(for: request), "A late scene must not recreate a canceled transfer.")

        let stale = try XCTUnwrap(fixture.coordinator.prepareTearOff(item, from: source.id))
        source.browser.closeTab(tab.id)
        XCTAssertFalse(fixture.coordinator.completePendingTransfer(to: stale.id))
        XCTAssertNil(fixture.coordinator.existingModel(for: stale.id))
    }

    func testClosingOneNormalWindowKeepsTheOtherWindowAndSharedTabs() throws {
        let fixture = makeFixture()
        let first = try XCTUnwrap(fixture.coordinator.model(for: .initial))
        let second = try XCTUnwrap(
            fixture.coordinator.model(for: .normal(sourceWindowID: first.id)))
        let tabID = try XCTUnwrap(first.browser.shownTab?.id)
        first.pages.select()
        second.pages.select()
        let page = try XCTUnwrap(second.pages.activePage)

        fixture.coordinator.closeWindow(first.id)

        XCTAssertEqual(second.browser.shownTab?.id, tabID)
        XCTAssertTrue(second.pages.activePage === page)
        XCTAssertNotNil(fixture.coordinator.existingModel(for: second.id))
        XCTAssertTrue(fixture.browser.spaceModels.contains { $0.tabs.contains(tabID) })
    }

    func testCancelingAPreparedNativeTearOffClosesItsShellAndRejectsLateAttachment() throws {
        let fixture = makeFixture()
        let source = try XCTUnwrap(fixture.coordinator.model(for: .initial))
        let tab = try XCTUnwrap(source.browser.shownTab)
        let space = try XCTUnwrap(source.browser.shownSpace)
        let request = try XCTUnwrap(
            fixture.coordinator.prepareTearOff(
                BrowserTabDragItem(tabID: tab.id, spaceID: space.id, profileID: space.profileID),
                from: source.id, at: CGPoint(x: 500, y: 500)))
        let window = NSWindow(
            contentRect: CGRect(x: 100, y: 100, width: 900, height: 600),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        fixture.coordinator.preparePresentation(window, for: request.id)
        window.orderFront(nil)

        fixture.coordinator.cancelPendingTransfer(to: request.id)

        XCTAssertFalse(window.isVisible)
        XCTAssertNil(fixture.coordinator.existingModel(for: request.id))
        XCTAssertFalse(fixture.coordinator.attach(window, to: request.id))
        XCTAssertFalse(window.isVisible)
        XCTAssertEqual(source.browser.shownTab?.id, tab.id)
    }

    func testACommittedTearOffRemainsAvailableWhenItsRowCannotBeMeasured() async throws {
        let fixture = makeFixture()
        let source = try XCTUnwrap(fixture.coordinator.model(for: .initial))
        let tab = try XCTUnwrap(source.browser.shownTab)
        let space = try XCTUnwrap(source.browser.shownSpace)
        let request = try XCTUnwrap(
            fixture.coordinator.prepareTearOff(
                BrowserTabDragItem(tabID: tab.id, spaceID: space.id, profileID: space.profileID),
                from: source.id, at: CGPoint(x: 500, y: 500)))
        let destination = try XCTUnwrap(fixture.coordinator.existingModel(for: request.id))
        let placement = try XCTUnwrap(destination.tearOffPlacement)
        let window = NSWindow(
            contentRect: CGRect(x: 100, y: 100, width: 900, height: 600),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer {
            fixture.coordinator.closeWindow(destination.id)
            fixture.coordinator.closeWindow(source.id)
            window.close()
        }
        fixture.coordinator.preparePresentation(window, for: request.id)
        XCTAssertTrue(window.ignoresMouseEvents)
        XCTAssertTrue(fixture.coordinator.attach(window, to: request.id))
        XCTAssertEqual(destination.browser.shownTab?.id, tab.id)

        for _ in 0..<80 where placement.isPending {
            try await Task.sleep(for: .milliseconds(25))
        }

        XCTAssertFalse(placement.isPending)
        XCTAssertTrue(window.isVisible)
        XCTAssertFalse(window.ignoresMouseEvents)
        XCTAssertEqual(destination.browser.shownTab?.id, tab.id)
        XCTAssertTrue(source.browser.shownSpace?.tabs.models.isEmpty == true)
    }

    /// A lifted row's payload comes back as the same row; the selection the
    /// lift captured stays with the lift and never enters the payload.
    func testDragItemsSurviveTheirTransferEncoding() throws {
        let browser = BrowserStore(seed: .preview)
        let space = try XCTUnwrap(browser.shownSpace)
        let tabs = space.tabs.models.filter { !$0.isStartPage }.prefix(2).map(\.id)
        let selection = try XCTUnwrap(browser.capturedSelection(ids: tabs))
        var tab = BrowserTabDragItem(
            tabID: tabs[0], spaceID: space.id, profileID: space.profileID, selection: selection)
        var folder = BrowserFolderDragItem(
            folderID: UUID(), spaceID: space.id, profileID: space.profileID, memberTabIDs: tabs,
            selection: selection)
        var split = BrowserSplitGroupDragItem(
            groupID: UUID(), spaceID: space.id, profileID: space.profileID, memberTabIDs: tabs,
            selection: selection)
        let decodedTab = try JSONDecoder().decode(BrowserTabDragItem.self, from: JSONEncoder().encode(tab))
        let decodedFolder = try JSONDecoder().decode(BrowserFolderDragItem.self, from: JSONEncoder().encode(folder))
        let decodedSplit = try JSONDecoder().decode(BrowserSplitGroupDragItem.self, from: JSONEncoder().encode(split))
        (tab.selection, folder.selection, split.selection) = (nil, nil, nil)

        XCTAssertEqual(decodedTab, tab)
        XCTAssertEqual(decodedFolder, folder)
        XCTAssertEqual(decodedSplit, split)
    }

    private func makeNativeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: CGRect(x: 100, y: 100, width: 900, height: 600),
            styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        return window
    }

    private func makeCoordinator(over browser: BrowserStore) -> BrowserMacWindowCoordinator {
        BrowserMacWindowCoordinator(
            browser: browser, pages: BrowserPagePool(browser: browser),
            spaceAccess: BrowserSpaceAccessController(), windowLayouts: BrowserWindowLayouts(defaults: nil))
    }

    private func makeFixture() -> (browser: BrowserStore, coordinator: BrowserMacWindowCoordinator) {
        let tab = TabState.Seed(title: "Window lifecycle", url: URL(string: "about:blank"), placement: .current)
        let space = SpaceState.Seed(
            name: "Window lifecycle", symbol: "globe",
            accent: .indigo, folders: [], tabs: [tab])
        let browser = BrowserStore.hostingPages(
            SessionState.Seed(spaces: [space]),
            showing: space.id, tabs: [space.id: tab.id])
        let pages = BrowserPagePool(browser: browser)
        return (
            browser,
            BrowserMacWindowCoordinator(
                browser: browser, pages: pages, spaceAccess: BrowserSpaceAccessController(),
                windowLayouts: BrowserWindowLayouts(defaults: nil))
        )
    }
}
