import CoreGraphics

/// The controls a shell asks the Space switcher to carry alongside its
/// Spaces.
///
/// Only an arrangement with room either side of its picker can carry any, so
/// each one is optional and the scrolling track ignores both. They are inputs
/// rather than a fixed pair because the same strip should be able to lose the
/// sidebar toggle — a docked window has nothing to toggle — without the
/// switcher learning about docking.
struct BrowserSpaceSwitcherAccessories {
    var sidebarToggle: BrowserSpaceSwitcherSidebarToggle?
    var commonLists: BrowserSpaceSwitcherCommonLists?
}

/// The switcher's accessory at the window's edge: show or hide the sidebar
/// the switcher is standing in.
struct BrowserSpaceSwitcherSidebarToggle {
    let action: BrowserSidebarToggleAction
    let toggle: () -> Void
}

/// The switcher's accessory on the page side: the archive, history, and
/// downloads lists, and the badge that says how many finished downloads have
/// not been looked at yet.
struct BrowserSpaceSwitcherCommonLists {
    let isExpanded: Bool
    let toggle: () -> Void

    /// Reports where the trigger ended up, so the lists can fan out from it.
    let recordTriggerFrame: (CGRect) -> Void
}
