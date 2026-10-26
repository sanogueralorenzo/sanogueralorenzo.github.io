import XCTest

@testable import Crest

@MainActor
final class BrowserSettingsPrivacyPolicyTests: XCTestCase {
    func testLiveSpaceSelectionRejectsStaleSourcesAndUnavailableDestinationsWithoutMutation() {
        for invalidation in SettingsSelectionInvalidation.allCases {
            var session = SessionState.Seed.preview
            let settings = TabState.Seed(title: "Settings", url: nil, nativeContent: .settings, placement: .current)
            // A tab that shows something else now, under the identity the
            // Settings tab had when the selection was captured.
            session.spaces[0].tabs.append(
                invalidation == .replacedTabContent
                    ? TabState.Seed(
                        id: settings.id, title: "Replacement", url: nil,
                        nativeContent: .init(kind: "replacement-document"),
                        placement: .current)
                    : settings)
            let source = session.spaces[0]
            let destination = session.spaces[1]
            let browser = BrowserStore(seed: session)
            browser.selectSpace(source.id)
            let action = BrowserSettingsSpaceSelectionAction(
                browser: browser)
            let assignment = BrowserTabRuntimeAssignment(
                tabID: settings.id, spaceID: source.id, profileID: source.profileID)
            switch invalidation {
            case .removedTab:
                browser.deleteTab(settings.id, in: source.id)
            case .replacedTabContent:
                break
            case .replacedProfile:
                browser.replaceProfileForTesting(of: source.id)
            case .unselectedSource:
                browser.selectPresentedSpace(destination.id)
            case .deletingSource:
                _ = browser.family.beginDeletingSpace(source.id)
            case .deletingDestination:
                _ = browser.family.beginDeletingSpace(destination.id)
            case .missingDestination:
                browser.removeSpaceForTesting(destination.id)
            }
            let before = browser.sessionSeed
            let revision = browser.sessionRevision

            XCTAssertNil(action.select(destination.id, matching: assignment), "\(invalidation)")

            XCTAssertEqual(browser.sessionSeed, before, "\(invalidation)")
            XCTAssertEqual(browser.sessionRevision, revision, "\(invalidation)")
        }
    }

}

private enum SettingsSelectionInvalidation: CaseIterable {
    case removedTab, replacedTabContent, replacedProfile, unselectedSource, deletingSource
    case deletingDestination, missingDestination
}
