import SwiftUI

/// Everything the root sidebar owns, handed to the shell that lays it out.
///
/// The root holds the state both shells kept separately — the pending page
/// selection, the utility search and filter, the clear-history confirmation —
/// and the flows that read it. A shell's layout is still its own, so the root
/// passes this down rather than composing the chrome itself: whichever view the
/// shell builds asks the context for the Spaces, the ports, and the callbacks
/// instead of re-deriving them.
///
/// The Spaces are read here rather than in each consumer so Observation tracks
/// them once, in the root's body, for every view the shell hangs off this.
@MainActor
struct BrowserSidebarContext {
    let sidebarInteraction: BrowserSidebarInteractionState
    let browser: BrowserStore
    let pageAccess: BrowserSidebarPageAccess
    let spaceAccess: BrowserSpaceAccessController

    /// What the hosting shell can do, resolved once by the host.
    let capabilities: BrowserInteractionCapabilities

    /// The Spaces the sidebar may show, with the ones being deleted left out.
    let availableSpaces: [SpaceModel]

    let utilityPresentation: BrowserUtilityPresentationState
    let utilityActions: BrowserUtilityListActions
    let utilitySearchText: Binding<String>
    let utilityFilter: Binding<BrowserUtilityListFilter>

    /// Where this shell puts the presentation the chrome asks for.
    let chromeActions: BrowserSidebarChromeActions

    /// Moves the selection, and whatever page presentation follows from it.
    let selectSpace: (UUID) -> Void

    /// Tells the root that the pager came to rest on a Space, which is what
    /// releases a deferred page selection.

    /// Asks for the clear-history confirmation for one Space. The root refuses
    /// unless that Space is still the selected, unlocked one.
    let confirmClearHistory: (SpaceModel) -> Void

    /// Dismisses an open utility surface because the reader tapped the sidebar
    /// itself rather than anything in it.
    let dismissUtilityOnBlankSpace: () -> Void

    /// Opens or closes the archive, history, and downloads switcher, landing on
    /// downloads when some have not been looked at yet.
    let toggleUtilitySwitcher: () -> Void
}
