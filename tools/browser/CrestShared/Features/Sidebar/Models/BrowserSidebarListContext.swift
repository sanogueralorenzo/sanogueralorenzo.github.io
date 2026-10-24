import SwiftUI

/// Everything the lists of one Space's sidebar draw from and act through, the
/// same for every row of that Space: the Space and the window as the read
/// model keeps them, the images tabs wear, and the collaborators a row acts
/// through. A row reads what it shows from its own objects, so the context
/// never changes while the Space stays on screen.
///
/// Two contexts are equal when they name the same objects. The actions a
/// context carries reach only those objects and the Space's identity, which
/// is why comparing them is not needed: SwiftUI leaves a row alone when its
/// parent hands it the same objects again.
struct BrowserSidebarListContext {
    // MARK: - Variables

    let space: SpaceModel
    let window: WindowStateModel
    let favicons: FaviconAssets
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    let pageAccess: BrowserSidebarPageAccess
    let tabActions: BrowserSidebarTabActions
    let capabilities: BrowserInteractionCapabilities
    /// The namespace each section's rows anchor the page they open in, where
    /// the shell anchors that section's rows at all.
    var promotionNamespaces: [TabPlacement: Namespace.ID] = [:]
    /// What opening a tab means to the host. The rows decide *whether*; the
    /// host decides what appears.
    let select: (UUID) -> Void
    /// How a saved or pinned tab gets back to the page it was saved from, where
    /// the host offers it.
    var restoreSavedLocation: ((UUID) -> Void)? = nil

    /// The Space as the actions name it. A Space keeps its profile while it is
    /// on screen; a new profile is a new page.
    @MainActor var assignment: BrowserSpaceRuntimeAssignment {
        BrowserSpaceRuntimeAssignment(spaceID: space.id, profileID: space.profileID)
    }

    @MainActor var profileID: UUID { space.profileID }

    // MARK: - Actions - Reading

    /// The namespace the rows of `section` anchor their pages in.
    func promotionNamespace(for section: TabPlacement) -> Namespace.ID? {
        promotionNamespaces[section]
    }

    /// Whether the tab holds a resident page in this window. Reading it
    /// observes the page layer's residency.
    @MainActor func isLoaded(_ tabID: UUID) -> Bool {
        pageAccess.containsResidentPage(tabID)
    }

    /// Whether another page shares the tab's page as a tab. Reading it
    /// observes the page's sharing.
    @MainActor func isSharedAsTab(_ tabID: UUID) -> Bool {
        pageAccess.isSharedAsTab(runtimeAssignment(of: tabID))
    }

    /// Whether the tab's page shares another tab. Reading it observes the
    /// page's sharing.
    @MainActor func isSharingTab(_ tabID: UUID) -> Bool {
        pageAccess.isSharingTab(runtimeAssignment(of: tabID))
    }

    /// Whether the tab's page takes part in tab sharing: shared by another
    /// page, or sharing another tab with the site it shows.
    @MainActor func takesPartInTabSharing(_ tabID: UUID) -> Bool {
        let assignment = runtimeAssignment(of: tabID)
        return pageAccess.isSharedAsTab(assignment) || pageAccess.isSharingTab(assignment)
    }

    /// Whether the window shows this Space, unlocked, so its rows may act.
    @MainActor var isCurrentAndUnlocked: Bool {
        isCurrent(assignment)
    }

    /// Whether the window shows the Space `assignment` names, unlocked, with
    /// the same profile, so a row drawn for it may act. A row captures its
    /// assignment when it draws; a profile replaced since refuses it. Reading
    /// it observes which Space the window shows, the Space's membership and
    /// profile, and the Space's lock.
    @MainActor func isCurrent(_ assignment: BrowserSpaceRuntimeAssignment) -> Bool {
        guard window.shownSpaceID == assignment.spaceID, browser.spaceModel(assignment.spaceID) === space,
            space.profileID == assignment.profileID
        else { return false }
        return !spaceAccess.isLocked(space)
    }

    /// Whether a row drawn for the tab `assignment` names may act on it: the
    /// window shows its Space, unlocked, and the Space still holds the tab.
    @MainActor func isTabCurrent(_ assignment: BrowserTabRuntimeAssignment) -> Bool {
        isCurrent(BrowserSpaceRuntimeAssignment(spaceID: assignment.spaceID, profileID: assignment.profileID))
            && space.tabs.contains(assignment.tabID)
    }

    // MARK: - Actions - Tabs

    /// The tab at the other end of the tab sharing the tab's page takes part
    /// in, when Crest knows it and the Space holds it.
    @MainActor func tabSharingCounterpart(of tabID: UUID) -> TabStateModel? {
        pageAccess.tabSharingCounterpartID(runtimeAssignment(of: tabID)).flatMap { space.tabs.model($0) }
    }

    /// Stops every tab sharing the tab's page takes part in.
    @MainActor func stopTabSharing(_ tabID: UUID) {
        pageAccess.stopTabSharing(runtimeAssignment(of: tabID))
    }

    /// The media session the tab's page publishes. Reading it observes the
    /// published sessions.
    @MainActor func mediaSession(of tabID: UUID) -> BrowserMediaSessionSnapshot? {
        pageAccess.mediaSession(runtimeAssignment(of: tabID))
    }

    /// Mutes or unmutes the sound the tab's page plays.
    @MainActor func setMuted(_ muted: Bool, of tabID: UUID) {
        pageAccess.setMuted(muted, runtimeAssignment(of: tabID))
    }

    /// The color the tab's page declares for itself, when it declares one.
    /// Reading it observes the page's theme.
    @MainActor func siteThemeAccent(of tabID: UUID) -> BrowserTabIconAccent? {
        pageAccess.siteThemeIconAccent(runtimeAssignment(of: tabID))
    }

    /// The engine's measure of the sound the tab's page plays, where its
    /// engine measures it.
    @MainActor func audioSpectrum(of tabID: UUID) -> BrowserAudioSpectrumFeed? {
        pageAccess.audioSpectrum(runtimeAssignment(of: tabID))
    }

    @MainActor func unload(_ tabID: UUID) {
        pageAccess.unloadPage(tabID, assignment)
    }

    @MainActor func pullNewIcon(_ tabID: UUID) {
        let actions = tabActions
        Task { await actions.pullNewIcon(for: tabID) }
    }

    /// The tab as the page layer names it: in this Space, with its profile.
    @MainActor private func runtimeAssignment(of tabID: UUID) -> BrowserTabRuntimeAssignment {
        BrowserTabRuntimeAssignment(tabID: tabID, spaceID: space.id, profileID: space.profileID)
    }
}

extension BrowserSidebarListContext: Equatable {
    static func == (lhs: BrowserSidebarListContext, rhs: BrowserSidebarListContext) -> Bool {
        lhs.space === rhs.space && lhs.window === rhs.window && lhs.favicons === rhs.favicons
            && lhs.browser === rhs.browser && lhs.spaceAccess === rhs.spaceAccess
            && lhs.capabilities == rhs.capabilities && lhs.promotionNamespaces == rhs.promotionNamespaces
            && (lhs.restoreSavedLocation == nil) == (rhs.restoreSavedLocation == nil)
    }
}
