import SwiftUI

/// Uses one input policy for pinned tiles and their drop targets.
struct BrowserPinnedTabsDropSection: View {
    @Environment(BrowserSidebarInteractionState.self) private var sidebarInteraction

    let context: BrowserSidebarListContext

    var body: some View {
        BrowserPinnedTabsGrid(context: context)
            .frame(minHeight: metrics.sectionEndBandHeight)
            .contentShape(.rect)
            .browserSidebarReorderSectionIndicator(
                .tabs(placement: .pinned, folderID: nil),
                state: sidebarInteraction.sidebarReorderState
            )
            // On the whole section, not just the empty placeholder: a zone inside
            // one branch vanishes the moment any tab is pinned, and dragging into a
            // populated grid becomes impossible.
            .browserSidebarReorderZone(
                .section(.tabs(placement: .pinned, folderID: nil)),
                state: sidebarInteraction.sidebarReorderState,
                minimumHeight: metrics.sectionEndBandHeight
            )
            .accessibilityHint("Drop a tab here to pin it")
            .environment(\.browserInteractionCapabilities, context.capabilities)
    }

    private var metrics: BrowserSidebarTabListMetrics {
        context.capabilities.tabListMetrics
    }
}

/// The pinned tabs the core lists, as a grid. It reads only the pinned list
/// and the tabs it names; each tile reads the rest.
private struct BrowserPinnedTabsGrid: View {
    @Environment(BrowserSidebarInteractionState.self) private var sidebarInteraction

    let context: BrowserSidebarListContext

    var body: some View {
        let space = context.space
        PinnedTabGrid(
            tabs: space.sidebar.section(.pinned).rows.compactMap { space.tabs.model($0.id) },
            favicons: context.favicons,
            assignment: context.assignment,
            window: context.window,
            select: { runtimeAssignment in
                guard context.isCurrentAndUnlocked else { return }
                context.select(runtimeAssignment.tabID)
            },
            context: context,
            dragState: sidebarInteraction.tabDragState,
            siteThemeAccent: context.pageAccess.siteThemeIconAccent,
            promotionNamespace: context.promotionNamespace(for: .pinned),
            capabilities: context.capabilities
        )
    }
}

extension BrowserPinnedTabsDropSection: @MainActor Equatable {
    /// The section is equal to one over the same Space and window, as SwiftUI
    /// compares a view's inputs: a page that redraws for anything else leaves
    /// the grid alone.
    static func == (lhs: BrowserPinnedTabsDropSection, rhs: BrowserPinnedTabsDropSection) -> Bool {
        lhs.context == rhs.context
    }
}
