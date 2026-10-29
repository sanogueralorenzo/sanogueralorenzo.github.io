import Foundation
import XCTest

@testable import Crest

@MainActor
final class NativeClosePreparationTests: XCTestCase {
    @MainActor
    private final class Recorder {
        var checked: [UUID] = []
        var answers: [@MainActor (Bool) -> Void] = []
        var prompts: [any CorePromptChange] = []
        func check(_ id: UUID, _ answer: @escaping @MainActor (Bool) -> Void) {
            checked.append(id)
            answers.append(answer)
        }
    }
    @MainActor
    private final class Context {
        let core: CrestCore
        let browser: BrowserStore
        let recorder = Recorder()
        var held: [Engines.OpenedPage] = []
        lazy var closing = NativeClosePreparation(core: core, check: recorder.check) { [weak self] in
            self?.recorder.prompts.append($0)
        }
        init(platform: DevicePlatform = .desktop) throws {
            core = try CrestCore(
                configuration: AppConfiguration(storageDirectory: nil, platform: platform, importNames: nil))
            core.engines.register(
                WebKitEngineBinding(
                    profileStores: WebKitBrowserWebsiteDataStoreRemover(), contentBlocking: WebKitContentBlocking()))
            browser = BrowserStore(
                seed: SessionState.Seed(spaces: [
                    SpaceState.Seed(name: "Work", tabs: []), SpaceState.Seed(name: "Personal", tabs: []),
                ]), core: core)
        }
        func page(in browser: BrowserStore? = nil, window: UUID? = nil) throws -> UUID {
            let owner = browser ?? self.browser
            let id = UUID()
            let opened = try XCTUnwrap(
                core.engines.open(
                    OpenPage(
                        pageID: id, workspaceID: owner.family.workspaceID, spaceID: owner.spaceModels[0].id, tabID: nil,
                        windowID: window ?? owner.windowID, transient: nil, openerPageID: nil)))
            held.append(opened)
            core.drain()
            XCTAssertEqual(core.state.pages[id]?.phase, .live)
            return id
        }
        func commit(_ page: UUID, sameDocument: Bool = false) throws {
            core.engines.report(
                NavigationCommitted(pageID: page, url: "https://example.com/new", sameDocument: sameDocument),
                from: try XCTUnwrap(core.engines.webKit))
            core.drain()
        }
    }
    func testPagesAreAskedInOrderOnceAndTheFirstDeclineStopsThePreparation() throws {
        let context = try Context()
        let first = try context.page()
        let second = try context.page()
        let third = try context.page()
        var result: [Bool] = []
        let request = UUID()
        try context.closing.prepare(PrepareToClosePages(requestID: request, pageIDs: [first, first, second, third])) {
            result.append($0)
        }
        XCTAssertEqual(context.recorder.checked, [first])
        XCTAssertThrowsError(try context.closing.prepare(PrepareToQuit(requestID: UUID())) { _ in }) {
            XCTAssertEqual($0 as? NativeClosePreparation.Failure, .preparationUnderway(request))
        }
        context.recorder.answers[0](true)
        XCTAssertEqual(context.recorder.checked, [first, second])
        context.recorder.answers[1](false)
        XCTAssertEqual(result, [false])
        XCTAssertNotNil(context.core.state.pages[first], "Preparation does not release pages")
        context.recorder.answers[1](true)
        XCTAssertEqual(result, [false])
        XCTAssertEqual(context.recorder.checked, [first, second])
    }
    func testAnEmptyCloseCanFinishWhileAnotherCloseWaits() throws {
        let context = try Context()
        let page = try context.page()
        var first: [Bool] = []
        var empty: [Bool] = []
        try context.closing.prepare(PrepareToClosePages(requestID: UUID(), pageIDs: [page])) { first.append($0) }
        try context.closing.prepare(PrepareToClosePages(requestID: UUID(), pageIDs: [UUID()])) { empty.append($0) }
        XCTAssertEqual(empty, [true])
        XCTAssertTrue(first.isEmpty)
        context.recorder.answers[0](true)
        XCTAssertEqual(first, [true])
    }
    func testANewDocumentInvalidatesApprovalButSameDocumentNavigationDoesNot() throws {
        for sameDocument in [false, true] {
            let context = try Context()
            let first = try context.page()
            let second = try context.page()
            var result: [Bool] = []
            try context.closing.prepare(PrepareToClosePages(requestID: UUID(), pageIDs: [first, second])) {
                result.append($0)
            }
            context.recorder.answers[0](true)
            let before = try XCTUnwrap(context.core.state.pages[first]).documents
            try context.commit(first, sameDocument: sameDocument)
            XCTAssertEqual(context.core.state.pages[first]?.documents, before + (sameDocument ? 0 : 1))
            context.recorder.answers[1](true)
            XCTAssertEqual(result, [sameDocument])
        }
    }
    func testGonePagesAdvanceAndLateAnswersCannotSettleANewerRequest() throws {
        let context = try Context()
        let first = try context.page()
        let second = try context.page()
        var result: [Bool] = []
        let requestID = UUID()
        try context.closing.prepare(PrepareToClosePages(requestID: requestID, pageIDs: [first, second])) {
            result.append($0)
        }
        context.held[0].page.release(keepingState: false)
        context.core.drain()
        context.closing.prune()
        XCTAssertEqual(context.recorder.checked, [first, second])
        context.recorder.answers[0](false)
        XCTAssertTrue(result.isEmpty)
        context.recorder.answers[1](true)
        XCTAssertEqual(result, [true])
        var later: [Bool] = []
        try context.closing.prepare(PrepareToClosePages(requestID: requestID, pageIDs: [second])) { later.append($0) }
        context.recorder.answers[1](false)
        XCTAssertTrue(later.isEmpty)
        context.recorder.answers[2](true)
        XCTAssertEqual(later, [true])
    }
    func testWindowPreparationKeepsSharedPagesAndChecksBorrowedAndEndingPrivateWorkspaces() throws {
        let context = try Context()
        let ordinary = try context.page()
        let source = context.browser.spaceModels[1]
        let borrowed = try XCTUnwrap(
            context.browser.makeTemporaryWindowStore(in: BrowserSpaceRuntimeAssignment(space: source)))
        let tornPage = try context.page(in: borrowed)
        let privateBrowser = BrowserStore(
            seed: SessionState.Seed(spaces: [SpaceState.Seed(name: "Private", tabs: [])]),
            browsingMode: .privateBrowsing, core: context.core)
        let privatePage = try context.page(in: privateBrowser)
        let quickPrivate = try context.page(in: privateBrowser, window: context.browser.windowID)
        XCTAssertEqual(
            context.closing.pagesForWindows([context.browser.windowID]), [quickPrivate],
            "Shared pages stay; a private page hosted in this window still goes with it")
        XCTAssertEqual(context.closing.pagesForWindows([borrowed.windowID]), [tornPage])
        XCTAssertEqual(context.closing.pagesForWindows([privateBrowser.windowID]), [privatePage, quickPrivate])
        var result: [Bool] = []
        try context.closing.prepare(PrepareToCloseWindows(requestID: UUID(), windowIDs: [privateBrowser.windowID])) {
            result.append($0)
        }
        context.recorder.answers[0](true)
        context.recorder.answers[1](false)
        XCTAssertEqual(result, [false])
        XCTAssertEqual(context.recorder.checked, [privatePage, quickPrivate])
        XCTAssertNotNil(context.core.state.pages[ordinary])
    }
    func testAWorkspaceWithAnotherPrivateWindowOnlyAsksThatWindowsPagesAndMobilePagesAreNotShared() throws {
        let context = try Context()
        let privateBrowser = BrowserStore(
            seed: SessionState.Seed(spaces: [SpaceState.Seed(name: "Private", tabs: [])]),
            browsingMode: .privateBrowsing, core: context.core)
        let other = privateBrowser.makeWindowStore()
        let first = try context.page(in: privateBrowser)
        let second = try context.page(in: other)
        XCTAssertEqual(context.closing.pagesForWindows([privateBrowser.windowID]), [first])
        XCTAssertEqual(context.closing.pagesForWindows([privateBrowser.windowID, other.windowID]), [first, second])
        try context.core.send(
            MovePage(
                pageID: first, workspaceID: privateBrowser.family.workspaceID,
                spaceID: privateBrowser.spaceModels[0].id, tabID: nil, windowID: other.windowID))
        XCTAssertEqual(context.core.state.pages[first]?.windowID, other.windowID)
        XCTAssertTrue(context.closing.pagesForWindows([privateBrowser.windowID]).isEmpty)
        XCTAssertEqual(context.closing.pagesForWindows([other.windowID]), [first, second])
        let mobile = try Context(platform: .mobile)
        let page = try mobile.page()
        XCTAssertEqual(mobile.closing.pagesForWindows([mobile.browser.windowID]), [page])
    }
    func testQuitAsksAboutLiveDownloadsAndCancellationLeavesTheNextQuitAvailable() throws {
        let context = try Context()
        let page = try context.page()
        try context.core.send(
            BeginDownload(
                downloadID: UUID(), profileID: UUID(), filename: "file.txt", createdAt: Date(), isAcknowledged: false))
        var result: [Bool] = []
        try context.closing.prepare(PrepareToQuit(requestID: UUID())) { result.append($0) }
        XCTAssertTrue(context.closing.isQuitting)
        XCTAssertThrowsError(try context.closing.prepare(PrepareToQuit(requestID: UUID())) { _ in })
        XCTAssertTrue(context.closing.isQuitting, "Refusing another quit must not cancel the one already waiting")
        context.recorder.answers[0](true)
        let asked = try XCTUnwrap(context.recorder.prompts.first as? QuitWithDownloadsAsked)
        XCTAssertEqual(asked.liveDownloads, 1)
        XCTAssertEqual(context.recorder.checked, [page])
        XCTAssertTrue(result.isEmpty)
        try context.closing.answer(AnswerQuitWithDownloads(promptID: asked.promptID, quits: false))
        XCTAssertEqual(result, [false])
        XCTAssertFalse(context.closing.isQuitting)
        XCTAssertThrowsError(try context.closing.answer(AnswerQuitWithDownloads(promptID: asked.promptID, quits: true)))
        try context.closing.prepare(PrepareToQuit(requestID: UUID())) { result.append($0) }
        context.recorder.answers[1](true)
        let next = try XCTUnwrap(context.recorder.prompts.compactMap { $0 as? QuitWithDownloadsAsked }.last)
        try context.closing.answer(AnswerQuitWithDownloads(promptID: next.promptID, quits: true))
        XCTAssertEqual(result, [false, true])
        XCTAssertTrue(context.closing.isQuitting)
        XCTAssertEqual(
            context.recorder.prompts.compactMap { $0 as? PromptSettled }.map(\.promptID),
            [asked.promptID, next.promptID])
    }
    func testReentrantImmediateAnswersDoNotRecursivelyEnterWebKitAndUseOpeningOrder() throws {
        let context = try Context()
        let pages = try (0..<8).map { _ in try context.page() }
        XCTAssertEqual(context.core.state.pageOrder, pages)
        var depth = 0
        var maximum = 0
        var checked: [UUID] = []
        var result: [Bool] = []
        let closing = NativeClosePreparation(
            core: context.core,
            check: { id, answer in
                depth += 1
                maximum = max(maximum, depth)
                checked.append(id)
                answer(true)
                depth -= 1
            })
        try closing.prepare(PrepareToQuit(requestID: UUID())) { result.append($0) }
        XCTAssertEqual(checked, pages)
        XCTAssertEqual(result, [true])
        XCTAssertEqual(maximum, 1)
    }
    func testProductionPreparationChecksWebKitWithoutReleasingThePage() async throws {
        let context = try Context()
        let page = try context.page()
        var result: Bool?
        context.core.prepareToClose(PrepareToClosePages(requestID: UUID(), pageIDs: [page])) { result = $0 }
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while result == nil && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(25)) }
        XCTAssertEqual(result, true)
        XCTAssertEqual(context.core.state.pages[page]?.phase, .live)
        XCTAssertNotNil(context.core.engines.webKit?.page(page))
    }

    func testProductionPreparationAcceptsQuitBeforeWindowsCloseSoRelaunchKeepsThem() throws {
        let harness = try BrowserStoredSessionHarness(
            seed: SessionState.Seed(spaces: [SpaceState.Seed(name: "Work", tabs: [])]))
        let core = harness.core
        let saved = harness.store.makeWindowStore(BrowserWindowOpening(saved: true))
        var allowed: [Bool] = []
        core.prepareToClose(PrepareToQuit(requestID: UUID())) { allowed.append($0) }
        XCTAssertEqual(allowed, [true])
        XCTAssertTrue(core.isQuitting)
        try core.send(CloseWindow(windowID: saved.windowID))
        XCTAssertTrue(try core.query(LaunchWindows()).windowIDs.contains(saved.windowID))
    }
}
