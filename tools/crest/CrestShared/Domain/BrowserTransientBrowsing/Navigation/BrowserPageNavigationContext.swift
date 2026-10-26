import Foundation

struct BrowserPageNavigationContext: Equatable, Sendable {
    let tabID: UUID
    let title: String
    let customTitle: String?
    let placement: TabPlacement
    let savedURL: URL?
    let iconMode: TabIconMode
    let spaceAssignment: BrowserSpaceRuntimeAssignment
    let keepsPageLoaded: Bool

    var spaceID: UUID { spaceAssignment.spaceID }

    var assignment: BrowserSpaceRuntimeAssignment { spaceAssignment }

    /// The context of `tab` as the core published it, in the Space and
    /// profile its page runs in. A durable tab with no address of its own to
    /// return to keeps the one it shows.
    init(
        tab: TabState,
        spaceID: UUID,
        profileID: UUID
    ) {
        tabID = tab.id
        title = tab.displayTitle
        customTitle = BrowserShownTitle.resolve(tab.customTitle)
        placement = tab.placement
        savedURL = (tab.savedURL ?? (tab.placement.isDurable ? tab.url : nil)).flatMap(URL.init(string:))
        iconMode = tab.iconMode
        spaceAssignment = BrowserSpaceRuntimeAssignment(
            spaceID: spaceID,
            profileID: profileID
        )
        keepsPageLoaded = tab.keepsPageLoaded
    }

    /// A reader-supplied name always wins. Otherwise a resident page's current
    /// document title is more authoritative than the title last persisted for
    /// the tab, including while that page is playing in another Space.
    func mediaSessionOwnerTitle(observedPageTitle: String?) -> String? {
        customTitle
            ?? BrowserShownTitle.resolve(observedPageTitle)
            ?? BrowserShownTitle.resolve(title)
    }
}
