import Foundation
import WebKit
import XCTest

@testable import Crest

@MainActor
final class NativePagesTests: XCTestCase {
    @MainActor private final class Clock { var date = Date() }
    @MainActor private final class Context {
        let clock: Clock
        let core: CrestCore
        let binding: WebKitEngineBinding
        let browser: BrowserStore
        var held: [Engines.OpenedPage] = []
        var commands: [EngineCommand] = []
        var work: UUID { browser.spaceModels[0].id }
        init(platform: DevicePlatform = .desktop) throws {
            let clock = Clock()
            self.clock = clock
            core = try CrestCore(
                configuration: AppConfiguration(storageDirectory: nil, platform: platform, importNames: nil),
                pageClock: { clock.date })
            binding = WebKitEngineBinding(keepsProfilesInMemory: true)
            core.engines.register(binding)
            browser = BrowserStore(
                seed: SessionState.Seed(spaces: [
                    SpaceState.Seed(name: "Work", tabs: []), SpaceState.Seed(name: "Personal", tabs: []),
                ]), core: core)
            core.pages.commandIssued = { [weak self] in self?.commands.append($0) }
        }
        func tab(_ title: String = "Page", in space: UUID? = nil) throws -> UUID {
            try XCTUnwrap(
                browser.openSessionTab(
                    .page(URL(string: "https://example.com/" + title)!, title: title), in: space ?? work))
        }
        func open(_ tab: UUID?, window: UUID? = nil, opener: UUID? = nil) throws -> CorePage {
            let opened = try XCTUnwrap(
                core.engines.open(
                    OpenPage(
                        pageID: UUID(), workspaceID: browser.family.workspaceID,
                        spaceID: work, tabID: tab, windowID: window ?? browser.windowID, transient: nil,
                        openerPageID: opener)))
            held.append(opened)
            XCTAssertEqual(opened.page.state?.phase, .live)
            return opened.page
        }
        func show(
            _ page: CorePage, url: String = "https://example.com/loaded", title: String = "Loaded",
            loading: Bool = false, media: PageMediaActivity = []
        ) {
            page.report(
                PageStateChanged(
                    pageID: page.id,
                    snapshot: PageSnapshot(
                        url: url, pendingURL: nil, title: title,
                        isLoading: loading, security: .secure, media: media)))
        }
        func commit(_ page: CorePage, url: String = "https://example.com/loaded", title: String = "Loaded") {
            page.report(NavigationCommitted(pageID: page.id, url: url, sameDocument: false))
            page.report(NavigationFinished(pageID: page.id, url: url, title: title))
            show(page, url: url, title: title)
        }
    }
    func testOpeningAndMovingRefuseStaleScopesProfilesAndDuplicateOwnership() throws {
        let c = try Context()
        let tab = try c.tab()
        let page = try c.open(tab)
        let request = OpenPage(
            pageID: page.id, workspaceID: c.browser.family.workspaceID, spaceID: c.work,
            tabID: tab, windowID: c.browser.windowID, transient: nil, openerPageID: nil)
        XCTAssertThrowsError(try c.core.send(request)) {
            XCTAssertEqual($0 as? NativePages.Failure, .duplicatePage(page.id))
        }
        XCTAssertThrowsError(
            try c.core.send(
                OpenPage(
                    pageID: UUID(), workspaceID: request.workspaceID, spaceID: c.work,
                    tabID: tab, windowID: request.windowID, transient: nil, openerPageID: nil))
        ) {
            XCTAssertEqual($0 as? NativePages.Failure, .alreadyOwned(tab: tab, page: page.id))
        }
        let other = c.browser.spaceModels[1]
        XCTAssertThrowsError(
            try c.core.send(
                MovePage(
                    pageID: page.id, workspaceID: request.workspaceID, spaceID: other.id,
                    tabID: nil, windowID: request.windowID))
        ) { XCTAssertEqual($0 as? NativePages.Failure, .profileMismatch(page: page.id, space: other.id)) }
        XCTAssertEqual(page.state?.spaceID, c.work)
        let missing = UUID()
        XCTAssertThrowsError(
            try c.core.send(
                OpenPage(
                    pageID: UUID(), workspaceID: missing, spaceID: c.work,
                    tabID: nil, windowID: request.windowID, transient: nil, openerPageID: nil))
        ) {
            XCTAssertEqual($0 as? NativePages.Failure, .unknownWorkspace(missing))
        }
        try c.core.send(
            BeginDeletingSpace(
                workspaceID: request.workspaceID, windowID: request.windowID, spaceID: c.work, operationID: UUID()))
        XCTAssertThrowsError(
            try c.core.send(
                OpenPage(
                    pageID: UUID(), workspaceID: request.workspaceID, spaceID: c.work,
                    tabID: nil, windowID: request.windowID, transient: nil, openerPageID: nil))
        ) {
            XCTAssertEqual($0 as? NativePages.Failure, .spaceBeingDeleted(c.work))
        }
    }
    func testCopyUsesTheIssuingWindowsLiveAppearanceBeforeNavigationIsRecorded() throws {
        let c = try Context()
        let tab = try c.tab()
        let first = try c.open(tab)
        let sibling = UUID()
        try c.core.send(
            OpenWindow(
                windowID: sibling, workspaceID: c.browser.family.workspaceID, saved: false, copyingWindowID: nil,
                showingSpaceID: c.work, showingTabs: [], restoresTabs: true))
        let second = try c.open(tab, window: sibling)
        c.show(first, url: "https://first.example/", title: "First")
        c.show(second, url: "https://second.example/", title: "Second")
        let copied = try XCTUnwrap(c.browser.duplicateTab(tab, in: c.work))
        XCTAssertEqual(c.browser.spaceModel(c.work)?.tabs.model(copied)?.url, "https://first.example/")
        let changes = try c.core.send(
            DuplicateTab(
                workspaceID: c.browser.family.workspaceID, windowID: sibling, spaceID: c.work,
                tabID: tab, placement: nil, shows: true,
                appearances: c.core.pages.appearances(workspace: c.browser.family.workspaceID, window: sibling)))
        let id = try XCTUnwrap(
            changes.compactMap {
                if case .tabCopied(let copy) = $0 { return copy.copyTabID }
                return nil
            }.first)
        XCTAssertEqual(c.browser.spaceModel(c.work)?.tabs.model(id)?.url, "https://second.example/")
        XCTAssertEqual(c.browser.spaceModel(c.work)?.tabs.model(id)?.title, "Second")
    }
    func testOnlySoftwareOpenedPagesCanCloseTheirTabAndUnknownOpenerDoesNotGrantAuthority() throws {
        let c = try Context()
        let userTab = try c.tab("User")
        let user = try c.open(userTab)
        user.report(PageCloseRequested(pageID: user.id))
        XCTAssertNotNil(c.browser.spaceModel(c.work)?.tabs.model(userTab))
        let softwareTab = try c.tab("Software")
        let software = try c.open(softwareTab, opener: user.id)
        software.report(PageCloseRequested(pageID: software.id))
        XCTAssertNil(c.browser.spaceModel(c.work)?.tabs.model(softwareTab))
        let unknownTab = try c.tab("Unknown")
        let unknown = try c.open(unknownTab, opener: UUID())
        unknown.report(PageCloseRequested(pageID: unknown.id))
        XCTAssertNotNil(c.browser.spaceModel(c.work)?.tabs.model(unknownTab))
    }
    func testOfferedPopupIsHandedOverBeforeTheAdoptionObserverAndThenBecomesLive() throws {
        let c = try Context()
        let tab = try c.tab()
        let source = try c.open(tab)
        let built = try XCTUnwrap(c.held.first?.built)
        let offer = UUID()
        c.binding.offers[offer] = WebKitEngineBinding.Offer(
            popup: WebKitPopup(configuration: built.webView.configuration),
            space: c.browser.spaceModel(c.work), sourcePageID: source.id,
            request: URLRequest(url: URL(string: "https://popup.example/")!))
        defer {
            c.binding.offers[offer] = nil
            c.binding.adoptedOffers[offer] = nil
        }
        var adopted: OfferedPageAdopted?
        var wasHandedOver = false
        c.core.followAdoptedPages(c) { event in
            adopted = event
            if let opened = c.core.engines.host(event.pageID) {
                wasHandedOver = true
                c.held.append(opened)
            }
        }
        c.core.engines.report(
            PageOffered(
                offerID: offer, profileID: try XCTUnwrap(c.browser.spaceModel(c.work)).profileID,
                sourcePageID: source.id, windowID: nil, spaceID: nil, url: "https://popup.example/", foreground: true),
            from: c.binding)
        let event = try XCTUnwrap(adopted)
        XCTAssertTrue(wasHandedOver)
        XCTAssertEqual(c.core.state.pages[event.pageID]?.phase, .live)
        XCTAssertEqual(c.browser.selectedTabID(in: c.work), event.tabID)
        XCTAssertTrue(c.core.pages.page(event.pageID)?.openedByPage == true)
    }
    func testUnloadingRetainsColdHistoryAndClosingItsTabForgetsTheRetainedHistory() throws {
        let c = try Context()
        let tab = try c.tab()
        let page = try c.open(tab)
        let entries = (0..<3).map {
            PageHistoryEntry(id: UUID(), url: "https://history.example/\($0)", title: "Page \($0)")
        }
        c.commit(page, url: entries[1].url)
        page.report(PageHistoryReported(pageID: page.id, entries: entries, current: 1))
        page.release(keepingState: true)
        XCTAssertNil(c.core.state.pages[page.id])
        XCTAssertNotNil(c.core.pages.archivedHistory(page.id))
        let reopened = try c.open(tab)
        let fresh = PageHistoryEntry(id: UUID(), url: entries[1].url, title: "Fresh")
        reopened.report(PageHistoryReported(pageID: reopened.id, entries: [fresh], current: 0))
        let list = c.core.query(PageHistoryEntries(pageID: reopened.id))
        XCTAssertEqual(list.back.map(\.id), [entries[0].id])
        XCTAssertEqual(list.forward.map(\.id), [entries[2].id])
        reopened.release(keepingState: true)
        c.browser.closeTab(tab, in: c.work)
        XCTAssertNil(c.core.pages.archivedHistory(reopened.id))
    }
    func testIdleUnloadRechecksDocumentVisibilityMediaAndAgentHoldsAfterTheSilentCheck() throws {
        let c = try Context()
        let background = try c.tab("Background")
        let foreground = try c.tab("Foreground")
        c.browser.activateSessionTab(foreground, in: c.work)
        let page = try c.open(background)
        c.commit(page)
        c.clock.date.addTimeInterval(301)
        let candidate = try XCTUnwrap(c.core.query(IdlePages()).pages.first)
        c.show(page, media: .playing)
        try c.core.send(
            UnloadIdlePage(pageID: candidate.pageID, documents: candidate.documents, hiddenSince: candidate.hiddenSince)
        )
        XCTAssertNotNil(page.state)
        c.show(page)
        c.core.state.agentSessions = [
            AgentSessionState(
                sessionID: UUID(), identity: AgentIdentity(teamID: nil, signingID: nil, path: nil, client: "test"),
                name: "Test", color: nil, tabIDs: [background], opensWindows: false, activity: [])
        ]
        XCTAssertTrue(c.core.query(IdlePages()).pages.isEmpty)
        c.core.state.agentSessions = []
        page.report(NavigationCommitted(pageID: page.id, url: "https://new.example/", sameDocument: false))
        try c.core.send(
            UnloadIdlePage(pageID: candidate.pageID, documents: candidate.documents, hiddenSince: candidate.hiddenSince)
        )
        XCTAssertNotNil(page.state)
        let current = try XCTUnwrap(c.core.query(IdlePages()).pages.first)
        c.browser.activateSessionTab(background, in: c.work)
        try c.core.send(
            UnloadIdlePage(pageID: current.pageID, documents: current.documents, hiddenSince: current.hiddenSince))
        XCTAssertNotNil(page.state)
    }
    func testMemoryPressureUsesCrestsPlatformBudgetsAndLeavesPlayingPagesAlone() throws {
        for platform in [DevicePlatform.desktop, .mobile] {
            let c = try Context(platform: platform)
            let background = try c.tab("Background")
            let playing = try c.tab("Playing")
            let foreground = try c.tab("Foreground")
            c.browser.activateSessionTab(foreground, in: c.work)
            let page = try c.open(background)
            let media = try c.open(playing)
            c.commit(page)
            c.commit(media)
            c.show(media, media: .playing)
            try c.core.send(ReportMemoryPressure(level: .warning))
            XCTAssertEqual(page.state == nil, platform == .desktop)
            XCTAssertNotNil(media.state)
            if platform == .mobile {
                try c.core.send(ReportMemoryPressure(level: .critical))
                XCTAssertNil(page.state)
            }
        }
    }
    func testCommandDeliveryDoesNotReenterAndLateReportsCannotReviveReleasedPages() throws {
        let c = try Context()
        let first = try c.open(nil)
        let second = try c.open(nil)
        var closed: [UUID] = []
        var inCommand = false
        c.core.pages.commandIssued = { command in
            XCTAssertFalse(inCommand)
            inCommand = true
            if case .closePage(let close) = command {
                closed.append(close.pageID)
                if close.pageID == first.id { second.release(keepingState: false) }
            }
            inCommand = false
        }
        first.release(keepingState: false)
        XCTAssertEqual(closed, [first.id, second.id])
        c.core.engines.report(PageCreated(pageID: first.id), from: c.binding)
        c.core.engines.report(
            NavigationCommitted(pageID: first.id, url: "https://late.example/", sameDocument: false), from: c.binding)
        XCTAssertNil(c.core.state.pages[first.id])
        XCTAssertNil(c.core.state.pages[second.id])
    }
}
