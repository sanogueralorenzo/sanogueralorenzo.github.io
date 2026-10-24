import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserCommandPaletteCompletionTests: XCTestCase {
    func testProposalDoesNotEditOrNavigateAndAcceptanceRequiresLiveSource() async throws {
        let tab = TabState.Seed(title: "Example", url: URL(string: "https://example.com/path"), placement: .current)
        let space = makeSpace(tab)
        var available = true
        var navigated: URL?
        var inserted: String?
        let browser = BrowserStore(
            seed: SessionState.Seed(spaces: [space]), showing: space.id, tabs: [space.id: tab.id])
        let model = BrowserCommandPaletteModel(
            browser: browser, space: browser.spaceModel(space.id), selectedTabID: tab.id, initialQuery: "",
            commands: nil,
            isSourceAvailable: { _ in available }, selectTab: { _, _ in false },
            openURL: { _, url, _ in
                navigated = url
                return true
            }, dismiss: {})
        model.applyCompletion = { text, _ in inserted = text }
        model.updateCompletionEditing(text: "exa", selection: NSRange(location: 3, length: 0), isComposing: false)
        await model.waitForPendingResults()
        XCTAssertEqual(model.urlCompletion?.suffix, "mple.com")
        XCTAssertEqual(model.query, "exa")
        XCTAssertNil(navigated)
        XCTAssertNil(inserted)
        available = false
        XCTAssertNil(model.urlCompletion)
        XCTAssertFalse(model.acceptURLCompletion())
        XCTAssertNil(inserted)
        available = true
        XCTAssertTrue(model.acceptURLCompletion())
        XCTAssertEqual(inserted, "mple.com")
        XCTAssertNil(navigated)
    }

    func testLiveLockSelectionSpaceAndProfileChangesHideAndRejectCompletion() async {
        let tab = TabState.Seed(title: "Example", url: URL(string: "https://example.com/path"), placement: .current)
        let original = makeSpace(tab)
        let other = makeSpace(
            TabState.Seed(title: "Private", url: URL(string: "https://secret.example/path"), placement: .current))
        let browser = BrowserStore(
            seed: SessionState.Seed(spaces: [original, other]),
            showing: original.id, tabs: [original.id: tab.id])
        let access = BrowserSpaceAccessController()
        let model = BrowserCommandPaletteModel(
            browser: browser, space: browser.spaceModel(original.id), selectedTabID: tab.id, initialQuery: "",
            commands: nil,
            isSourceAvailable: {
                browser.isPaletteSourceAvailable($0, accessController: access)
            },
            selectTab: { _, _ in false }, openURL: { _, _, _ in false }, dismiss: {})
        model.applyCompletion = { _, _ in XCTFail("Stale proposal was accepted") }
        model.updateCompletionEditing(text: "exa", selection: NSRange(location: 3, length: 0), isComposing: false)
        await model.waitForPendingResults()
        XCTAssertNotNil(model.urlCompletion)
        browser.selectPresentedSpace(other.id)
        XCTAssertNil(model.urlCompletion)
        XCTAssertFalse(model.acceptURLCompletion())
        browser.removeSpaceForTesting(other.id)
        browser.updateSpaceAccessPolicy(.deviceOwnerAuthentication, in: original.id)
        XCTAssertNil(model.urlCompletion)
        XCTAssertFalse(model.acceptURLCompletion())
        browser.unlockForTesting(original)
        browser.updateSpaceAccessPolicy(.open, in: original.id)
        browser.clearPresentedTabSelection(in: original.id)
        XCTAssertNil(model.urlCompletion)
        browser.replaceProfileForTesting(of: original.id)
        browser.activateSessionTab(tab.id, in: original.id)
        XCTAssertNil(model.urlCompletion)
        XCTAssertFalse(model.acceptURLCompletion())
    }

    func testEmptySelectionCompletionCreatesDestinationOnlyAfterEnter() async {
        let tab = TabState.Seed(title: "Example", url: URL(string: "https://example.com/path"), placement: .saved)
        let space = makeSpace(tab)
        let browser = BrowserStore(
            seed: SessionState.Seed(spaces: [space]),
            showing: space.id, browsingMode: .privateBrowsing)
        var explicitSelectionCount = 0
        let actions = BrowserEmptySelectionPaletteActions(
            source: BrowserSpaceRuntimeAssignment(space: space), browser: browser,
            accessController: BrowserSpaceAccessController(), didSelectTab: { explicitSelectionCount += 1 })
        let model = BrowserCommandPaletteModel(
            browser: browser, space: browser.spaceModel(space.id), selectedTabID: nil, initialQuery: "", commands: nil,
            isSourceAvailable: { _ in false },
            selectTab: { _, _ in false }, openURL: { _, _, _ in false }, dismiss: {}, emptySelectionActions: actions)
        model.applyCompletion = { [weak model] insertion, range in
            guard let model else { return }
            let text = (model.query as NSString).replacingCharacters(in: range, with: insertion)
            model.updateCompletionEditing(
                text: text, selection: NSRange(location: text.utf16.count, length: 0), isComposing: false)
        }
        model.updateCompletionEditing(text: "exa", selection: NSRange(location: 3, length: 0), isComposing: false)
        await model.waitForPendingResults()
        XCTAssertNotNil(model.urlCompletion)
        XCTAssertTrue(model.acceptURLCompletion())
        XCTAssertNil(browser.shownTab)
        XCTAssertEqual(explicitSelectionCount, 0)
        // The site completes to its host, which the saved tab already shows, so
        // Return switches to that tab rather than opening the site again.
        model.activateSelectedResult()
        XCTAssertEqual(browser.shownTab?.address?.absoluteString, "https://example.com/path")
        XCTAssertEqual(explicitSelectionCount, 1)
        XCTAssertEqual(browser.shownSpace?.tabs.models.count, 1)
    }

    private func makeSpace(_ tab: TabState.Seed) -> SpaceState.Seed {
        SpaceState.Seed(
            name: "Current", symbol: "globe", accent: .indigo, folders: [],
            tabs: [tab])
    }

}
