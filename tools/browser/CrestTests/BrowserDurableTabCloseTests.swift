import XCTest

@testable import Crest

@MainActor
final class BrowserDurableTabCloseTests: XCTestCase {
    func testCloseResumesByDefaultAndResetPersistsWithoutChangingDurableIdentity() throws {
        for placement: TabPlacement in [.pinned, .saved] {
            for policy in SavedTabClosePolicy.all {
                let context = try makeContext(placement: placement)
                // The core puts the page away as the session's preferences say.
                let preferences = BrowserAppPreferenceStore()
                preferences.bind(to: context.browser, legacy: .unsaved)
                preferences.savedTabClosePolicy = policy
                let putAway = PutAwayPages(core: context.browser.core)
                let action = BrowserDurableTabCloseAction(
                    browser: context.browser, spaceAccess: BrowserSpaceAccessController())

                XCTAssertTrue(action.perform(context.assignment))

                let space = try XCTUnwrap(context.browser.spaceModel(context.assignment.spaceID)).value.seed
                var expected = context.tab
                if policy == .returnToSavedURL { expected.url = expected.savedURL ?? expected.url }
                XCTAssertEqual(space.tabs.first, expected)
                // The window that asked hears which page went, and whether it
                // keeps what brings it back.
                XCTAssertEqual(
                    putAway.pages.map { [$0.windowID, $0.spaceID, $0.tabID] },
                    [[context.browser.windowID, context.assignment.spaceID, context.tab.id]])
                XCTAssertEqual(putAway.pages.map(\.keepsState), [policy != .returnToSavedURL])
                XCTAssertNil(context.browser.shownTab)
                XCTAssertEqual(space.tabs.last, context.copy)
                XCTAssertEqual(space.archivedTabs, context.archived)
            }
        }
    }

    func testStaleLockedAndOrdinaryTabsDoNotCloseOrDiscardState() throws {
        for placement: TabPlacement in [.current, .pinned, .saved] {
            let context = try makeContext(placement: placement)
            let putAway = PutAwayPages(core: context.browser.core)
            let action = BrowserDurableTabCloseAction(
                browser: context.browser, spaceAccess: BrowserSpaceAccessController())
            let original = context.browser.sessionSeed
            let stale = BrowserTabRuntimeAssignment(
                tabID: context.tab.id, spaceID: context.assignment.spaceID, profileID: UUID()
            )
            XCTAssertFalse(action.perform(stale))
            if placement == .current { XCTAssertFalse(action.perform(context.assignment)) }
            XCTAssertEqual(context.browser.sessionSeed, original)

            context.browser.updateSpaceAccessPolicy(.deviceOwnerAuthentication, in: context.assignment.spaceID)
            XCTAssertFalse(action.perform(context.assignment))
            XCTAssertTrue(putAway.pages.isEmpty)
        }
    }

    func testDeferredCloseOnlyArchivesAfterApproval() throws {
        let context = try makeContext(placement: .current)
        let gate = DeferredDismissal()
        context.browser.family.pageDismissalAuthorizer = gate
        let original = context.browser.sessionSeed
        XCTAssertFalse(context.browser.closeTab(context.tab.id))
        XCTAssertEqual(context.browser.sessionSeed, original)
        XCTAssertFalse(gate.resolve(false))
        XCTAssertEqual(context.browser.sessionSeed, original)
        XCTAssertFalse(context.browser.closeTab(context.tab.id))
        XCTAssertTrue(gate.resolve(true))
        XCTAssertFalse(context.browser.shownSpace!.tabs.contains(context.tab.id))
        XCTAssertTrue(context.browser.shownSpace!.archive.contains(tabID: context.tab.id))
    }

    func testDeferredClearDoesNotCloseTabsOpenedWhileConfirmationWasPending() throws {
        let context = try makeContext(placement: .current)
        let gate = DeferredDismissal()
        context.browser.family.pageDismissalAuthorizer = gate
        let space = try XCTUnwrap(context.browser.shownSpace)
        XCTAssertFalse(context.browser.clearCurrentTabs(matching: BrowserSpaceRuntimeAssignment(space: space)))
        let newTab = try XCTUnwrap(context.browser.openNewTab(url: URL(string: "https://example.net/new")!))
        let beforeReply = context.browser.sessionSeed
        XCTAssertFalse(gate.resolve(true))
        XCTAssertEqual(context.browser.sessionSeed, beforeReply)
        XCTAssertTrue(context.browser.shownSpace!.tabs.contains(newTab))
    }

    func testDeferredCloseRechecksTheTabAssignment() throws {
        let context = try makeContext(placement: .current)
        let gate = DeferredDismissal()
        context.browser.family.pageDismissalAuthorizer = gate
        XCTAssertFalse(context.browser.closeTab(context.tab.id))
        context.browser.family.pageDismissalAuthorizer = nil
        context.browser.deleteTab(context.tab.id, in: context.assignment.spaceID)
        let beforeReply = context.browser.sessionSeed
        XCTAssertFalse(gate.resolve(true))
        XCTAssertEqual(context.browser.sessionSeed, beforeReply)
    }

    func testDurablePageIsNotRetiredWhenCloseIsCanceled() throws {
        let context = try makeContext(placement: .saved)
        let gate = DeferredDismissal()
        context.browser.family.pageDismissalAuthorizer = gate
        let putAway = PutAwayPages(core: context.browser.core)
        let action = BrowserDurableTabCloseAction(
            browser: context.browser, spaceAccess: BrowserSpaceAccessController())
        let original = context.browser.sessionSeed
        XCTAssertFalse(action.perform(context.assignment))
        XCTAssertTrue(putAway.pages.isEmpty)
        XCTAssertFalse(gate.resolve(false))
        XCTAssertTrue(putAway.pages.isEmpty)
        XCTAssertEqual(context.browser.sessionSeed, original)
        XCTAssertFalse(action.perform(context.assignment))
        XCTAssertTrue(gate.resolve(true))
        XCTAssertEqual(putAway.pages.map(\.tabID), [context.tab.id])
    }

    /// Hears each saved or pinned tab's page the core puts away.
    @MainActor
    private final class PutAwayPages {
        private(set) var pages: [TabPagePutAway] = []

        init(core: CrestCore) {
            core.followPutAwayPages(self) { [weak self] in self?.pages.append($0) }
        }
    }

    private final class DeferredDismissal: BrowserPageDismissalAuthorizing {
        var pending: (@MainActor () -> Bool)?
        func performDismissal(
            of assignments: [BrowserTabRuntimeAssignment], in browser: BrowserStore,
            operation: @escaping @MainActor () -> Bool
        ) -> Bool {
            pending = operation
            return false
        }
        func resolve(_ allowed: Bool) -> Bool {
            let operation = pending
            pending = nil
            return allowed && operation?() == true
        }
    }

    private func makeContext(placement: TabPlacement) throws -> Context {
        let root = try XCTUnwrap(URL(string: "https://example.com/root"))
        let child = try XCTUnwrap(URL(string: "https://example.com/child"))
        let tab = TabState.Seed(title: "Durable", url: child, savedURL: root, placement: placement)
        let copy = TabState.Seed(title: "Independent copy", url: child, placement: .current)
        let archived = [
            ArchivedTabState.Seed(
                tab: TabState.Seed(title: "Archive", url: child, placement: .current), archivedAt: .now,
                reason: .closed)
        ]
        let space = SpaceState.Seed(
            name: "Test", symbol: "circle", accent: .indigo,
            folders: [], tabs: [tab, copy], archivedTabs: archived
        )
        let browser = BrowserStore(
            seed: SessionState.Seed(spaces: [space]),
            showing: space.id, tabs: [space.id: tab.id]
        )
        return Context(
            browser: browser, tab: tab, copy: copy, archived: archived,
            assignment: BrowserTabRuntimeAssignment(tabID: tab.id, spaceID: space.id, profileID: space.profileID)
        )
    }

    private struct Context {
        let browser: BrowserStore
        let tab: TabState.Seed
        let copy: TabState.Seed
        let archived: [ArchivedTabState.Seed]
        let assignment: BrowserTabRuntimeAssignment
    }
}
