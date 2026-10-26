import SwiftUI

/// Everything a sidebar tab row is told, and the answers that follow from it.
@MainActor
struct BrowserSidebarTabRowConfiguration {
    // MARK: - Variables

    let tab: TabStateModel
    let context: BrowserSidebarListContext
    /// The Space the row was drawn for, as it stood then. An action checks it
    /// against the live Space, so a row drawn before a profile was replaced
    /// can never act for the replacement.
    let assignment: BrowserSpaceRuntimeAssignment
    /// Whether the window shows this tab: its own slot of the window's shown
    /// tabs, read by the row and handed to its parts as a value.
    let isSelected: Bool
    let isLoaded: Bool
    /// Whether this row is drawn inside a split group's container rather than
    /// standing on its own in the tab list.
    ///
    /// A grouped row is the same row in every other respect — same height,
    /// favicon, title, trailing control, menu, and selection accent. What it
    /// gives up is the sidebar's edge inset, which the container already
    /// provides.
    let isSplitGroupMember: Bool
    var spacePresentation: SidebarSpacePresentation? = nil

    var spaceID: UUID { assignment.spaceID }
    var profileID: UUID { assignment.profileID }
    var browser: BrowserStore { context.browser }
    var spaceAccess: BrowserSpaceAccessController { context.spaceAccess }
    var capabilities: BrowserInteractionCapabilities { context.capabilities }
    var favicons: FaviconAssets { context.favicons }
    var placement: TabPlacement { tab.placement }

    /// A tab the session keeps closes; one it outlives only unloads.
    var canClose: Bool { !tab.placement.isDurable }

    var promotionNamespace: Namespace.ID? {
        context.promotionNamespace(for: tab.placement)
    }

    var unload: ((UUID) -> Void)? {
        let context = context
        return { context.unload($0) }
    }

    var pullNewIcon: (() -> Void)? {
        let context = context
        let tabID = tab.id
        return { context.pullNewIcon(tabID) }
    }

    var restoreSavedLocation: (() -> Void)? {
        guard let restore = context.restoreSavedLocation else { return nil }
        let tabID = tab.id
        return { restore(tabID) }
    }

    var select: (UUID) -> Void { context.select }

    var metrics: BrowserSidebarTabRowMetrics {
        capabilities.tabRowMetrics
    }

    var trailingControlMetrics: BrowserTabTrailingControlMetrics {
        capabilities.trailingControlMetrics
    }

    /// The inset between the row's own bounds and its surface: the sidebar's
    /// layer inset, so the row lines up with every other layer. Zero inside a
    /// group, where the container's padding has already placed the row.
    var surfaceHorizontalInset: CGFloat {
        isSplitGroupMember ? 0 : BrowserSidebarMetrics.layerInset
    }

    /// The identity this row shares with the surface its page grows out of.
    var promotionID: String {
        BrowserTabPromotionID.value(for: tab.id)
    }

    var isPromotionSource: Bool {
        isSelected && !tab.isStartPage
    }

    var runtimeAssignment: BrowserTabRuntimeAssignment {
        BrowserTabRuntimeAssignment(
            tabID: tab.id,
            spaceID: spaceID,
            profileID: profileID
        )
    }

    /// Inactive pages retain their normal control appearance while commands
    /// remain guarded by the live selected Space below.
    var isAvailableForDisplay: Bool {
        guard let spacePresentation else { return isCurrentAndUnlocked }
        return spacePresentation.isAvailable(matching: assignment) && context.space.tabs.contains(tab.id)
    }

    /// Every action this row offers is refused unless the window shows the
    /// Space the row was drawn for, unlocked, with the same profile, and the
    /// Space still holds the tab.
    var isCurrentAndUnlocked: Bool {
        context.isCurrent(assignment) && context.space.tabs.contains(tab.id)
    }

    // MARK: - Initializers

    init(
        tab: TabStateModel, context: BrowserSidebarListContext, isSelected: Bool, isLoaded: Bool,
        isSplitGroupMember: Bool = false, spacePresentation: SidebarSpacePresentation? = nil
    ) {
        self.tab = tab
        self.context = context
        assignment = context.assignment
        self.isSelected = isSelected
        self.isLoaded = isLoaded
        self.isSplitGroupMember = isSplitGroupMember
        self.spacePresentation = spacePresentation
    }
}
