import SwiftUI

/// The sidebar's tab list, on every shell: the saved run, the seam below it, and
/// the current run.
///
/// The list owns the order those three appear in and nothing else. It reads
/// only whether the saved section is open; each section reads its own list, so
/// a move, a collapse or another shown tab never redraws it. Each shell wraps
/// it in its own scrolling chrome and drops this composition inside it.
struct BrowserSidebarTabList: View {
    let context: BrowserSidebarListContext
    /// Shows the saved section whatever the Space says, for a surface that
    /// always shows it.
    var alwaysShowsSavedTabs = false
    /// Whether the shell is in the state that reveals the seam's clear control —
    /// a pointer resting somewhere over the list.
    var showsClearAction = false
    let openNewTab: () -> Void

    var body: some View {
        let isSavedTabsExpanded = alwaysShowsSavedTabs || context.space.settings.isSavedTabsExpanded
        if isSavedTabsExpanded {
            BrowserSavedTabsDropSection(context: context)
                .transition(.opacity.combined(with: .move(edge: .top)))
        }

        BrowserCurrentTabsSeam(
            context: context, isSavedTabsExpanded: isSavedTabsExpanded, showsClearAction: showsClearAction)

        BrowserCurrentTabsDropSection(context: context, openNewTab: openNewTab)
    }
}

/// The seam between the saved run and the current one. It reads whether the
/// current run holds anything to clear and whether the saved run keeps a band
/// of its own, each observed apart from the rows, so a move never redraws it.
private struct BrowserCurrentTabsSeam: View {
    let context: BrowserSidebarListContext
    let isSavedTabsExpanded: Bool
    let showsClearAction: Bool

    var body: some View {
        let sidebar = context.space.sidebar
        BrowserCurrentTabsDivider(
            capabilities: context.capabilities,
            hasSavedTabsEndBand: isSavedTabsExpanded
                && (context.capabilities.showsRowDropIndicators || !sidebar.section(.saved).holdsTabRows),
            showsClearAction: showsClearAction,
            canClear: holdsCurrentTabs,
            clear: { _ = context.tabActions.clearCurrentTabs() }
        )
    }

    /// Whether the current section holds a tab, at its top level or in one of
    /// its folders. Its rows are read only when the top level holds folders
    /// and no tab.
    private var holdsCurrentTabs: Bool {
        let space = context.space
        let current = space.sidebar.section(.current)
        guard !current.holdsTabRows else { return true }
        guard !current.isEmpty else { return false }
        return current.rows.contains { $0.kind.opensList && !space.tabIDs(inFolder: $0.id).isEmpty }
    }
}

extension BrowserSidebarTabList: @MainActor Equatable {
    /// The list is equal to one over the same Space and window with the same
    /// settings, as SwiftUI compares a view's inputs: a page that redraws for
    /// anything else leaves the list alone.
    static func == (lhs: BrowserSidebarTabList, rhs: BrowserSidebarTabList) -> Bool {
        lhs.context == rhs.context && lhs.alwaysShowsSavedTabs == rhs.alwaysShowsSavedTabs
            && lhs.showsClearAction == rhs.showsClearAction
    }
}
