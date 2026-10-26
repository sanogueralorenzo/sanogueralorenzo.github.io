import Observation
import SwiftUI

/// The Getting Started practice: a practice workspace in a core of its own,
/// which starts from the core's practice Space and keeps nothing. Reusing the
/// real sidebar here must never let a practice gesture reach the person's
/// tabs. Its pages never load, so each practice tab wears the icon bundled
/// for it.
@Observable @MainActor
final class BrowserGettingStartedPractice {
    // MARK: - Variables

    private(set) var sidebarInteraction: BrowserSidebarInteractionState
    private(set) var browser: BrowserStore
    let spaceAccess = BrowserSpaceAccessController()
    let downloads = BrowserDownloadCenter(
        permissionCenter: BrowserSitePermissionCenter())
    let sidebarScroll = BrowserNativeScrollState()
    var splitWidths = BrowserSplitWidthTransaction(persistedFractions: [1])
    private var splitWidthMembers: [UUID] = []
    /// Each practice tab's identity in the practice the store holds.
    private var practiceTabIDs: [PracticeTab: UUID]

    /// The practice Space as the read model holds it.
    var space: SpaceModel {
        guard let model = browser.workspaceModel?.spaces.models.first else {
            preconditionFailure("The practice workspace always holds its one Space.")
        }
        return model
    }

    var assignment: BrowserSpaceRuntimeAssignment { BrowserSpaceRuntimeAssignment(space: space) }
    var selectedTabID: UUID? { browser.selectedTabID(in: space.id) }
    /// The cards the practice shows: the members of the split the selected
    /// tab shows in, or the selected tab alone, or none.
    var members: [TabStateModel] {
        guard let selectedTabID, let tab = space.tabs.model(selectedTabID) else { return [] }
        guard let groupID = space.shownSplit(containing: selectedTabID) else { return [tab] }
        return space.splitMembers(of: groupID)
    }

    // MARK: - Initializers

    init() {
        let opened = Self.opened()
        browser = opened.browser
        practiceTabIDs = opened.tabIDs
        sidebarInteraction = BrowserSidebarInteractionState.connected(to: opened.browser)
    }

    // MARK: - Actions - Practice

    /// The identity `tab` has in this practice.
    func tabID(_ tab: PracticeTab) -> UUID? {
        practiceTabIDs[tab]
    }

    /// Starts the practice over in a new practice workspace.
    func reset() {
        sidebarInteraction.cancel()
        let opened = Self.opened()
        browser = opened.browser
        practiceTabIDs = opened.tabIDs
        sidebarInteraction = BrowserSidebarInteractionState.connected(to: browser)
        splitWidthMembers = []
        reconcileSplitWidths()
    }

    /// A window over a new practice workspace, with each practice tab wearing
    /// its icon as a loaded page would leave it, and the practice tabs'
    /// identities in it.
    private static func opened() -> (browser: BrowserStore, tabIDs: [PracticeTab: UUID]) {
        let core = CrestCore()
        let browser = BrowserStore(
            credentialVault: InMemoryCredentialVault(), browsingMode: .standard,
            family: BrowserStoreFamily(startingAs: .practice, in: core), core: core)
        var identities: [PracticeTab: UUID] = [:]
        guard let space = browser.workspaceModel?.spaces.models.first else { return (browser, identities) }
        for tab in space.tabs.models {
            guard let practiceTab = PracticeTab.all.first(where: { $0.url == tab.url }) else { continue }
            identities[practiceTab] = tab.id
            if let icon = icon(of: practiceTab) {
                browser.setTabFavicon(icon, iconAccent: nil, for: tab.id, in: space.id)
            }
        }
        return (browser, identities)
    }

    private static func icon(of tab: PracticeTab) -> Data? {
        BrowserGettingStartedArtwork.favicon(tab.artwork)
    }

    func reconcileSplitWidths() {
        let ids = members.map(\.id)
        guard ids != splitWidthMembers else { return }
        splitWidthMembers = ids
        splitWidths.begin(fractions: Array(repeating: 1, count: max(1, ids.count)))
    }

    func addFolder(nested: Bool) {
        let parent =
            space.folders.models.first { $0.title == "Weekends" && $0.parentID == nil }?.id
            ?? browser.addFolder(title: "Weekends", in: space.id)
        if nested, let parent, !space.folders.models.contains(where: { $0.parentID == parent }) {
            _ = browser.addFolder(title: "Ideas", parentID: parent, in: space.id)
        }
    }

    func makeSplit() {
        guard let packingID = tabID(.packing), let trailID = tabID(.trail),
            space.tabs.contains(packingID), space.tabs.contains(trailID)
        else { return }
        browser.selectTab(trailID)
        _ = browser.addTabToSplit(
            BrowserTabDragItem(tabID: packingID, spaceID: space.id, profileID: space.profileID), joining: trailID,
            at: nil)
    }

    /// The practice has no pages, so the example tab opens as a loaded page
    /// would leave it: titled, and wearing the site's icon.
    func openExampleTab() {
        let example = PracticeTab.reading
        guard let url = URL(string: example.url),
            let id = browser.openSessionTab(.page(url, title: example.title), in: space.id),
            let favicon = Self.icon(of: example)
        else { return }
        _ = browser.setTabFavicon(favicon, iconAccent: nil, for: id, matching: assignment)
    }

    func move(_ id: UUID, by offset: Int) {
        browser.selectTab(id)
        _ = browser.moveSplitMember(id, by: offset, matching: assignment)
    }

    // MARK: - Actions - Sidebar

    /// The practice Space as the read model holds it, and what its rows act
    /// through, in the practice's own memory-only store.
    func listContext(capabilities: BrowserInteractionCapabilities) -> BrowserSidebarListContext? {
        guard let space = browser.workspaceModel?.spaces.models.first, let window = browser.windowModel else {
            return nil
        }
        return BrowserSidebarListContext(
            space: space, window: window, favicons: browser.core.state.favicons, browser: browser,
            spaceAccess: spaceAccess, pageAccess: pageAccess, tabActions: tabActions, capabilities: capabilities,
            select: { [browser] in browser.selectTab($0) }, restoreSavedLocation: { _ in })
    }

    var pageAccess: BrowserSidebarPageAccess {
        BrowserSidebarPageAccess(
            containsResidentPage: { _ in true }, containsResidentPageMatching: { _ in true },
            siteThemeIconAccent: { _ in nil }, residencyRevision: { 0 }, selectPages: {},
            deactivatePagePresentation: {}, unloadPage: { _, _ in }, pullFavicon: { _, _ in nil },
            downloadCenter: downloads)
    }

    var tabActions: BrowserSidebarTabActions {
        BrowserSidebarTabActions(
            assignment: assignment, browser: browser, reorderState: sidebarInteraction.sidebarReorderState,
            spaceAccess: spaceAccess,
            syncPagesAfterMutation: {}, pullFavicon: { _, _ in nil })
    }
}
