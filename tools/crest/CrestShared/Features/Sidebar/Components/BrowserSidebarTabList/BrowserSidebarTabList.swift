import SwiftUI

/// The sidebar's tab list, on every shell: the saved run, the seam below it, and
/// the current run.
///
/// Each section reads its own list, so a move or another shown tab never redraws
/// the whole list. Each shell wraps this composition in its own scrolling chrome.
struct BrowserSidebarTabList: View {
    let context: BrowserSidebarListContext
    /// Whether the shell is in the state that reveals the seam's clear control —
    /// a pointer resting somewhere over the list.
    var showsClearAction = false
    let openNewTab: () -> Void

    var body: some View {
        BrowserSavedTabsDropSection(context: context)

        BrowserCurrentTabsSeam(context: context, showsClearAction: showsClearAction)

        BrowserCurrentTabsDropSection(context: context)

        BrowserNewTabRow(capabilities: context.capabilities, action: openNewTab)
    }
}

/// The seam between the saved run and the current one. It reads whether the
/// current run holds anything to clear, observed apart from the rows so a move
/// never redraws them.
private struct BrowserCurrentTabsSeam: View {
    let context: BrowserSidebarListContext
    let showsClearAction: Bool

    var body: some View {
        if holdsCurrentTabs {
            BrowserCurrentTabsDivider(
                capabilities: context.capabilities,
                showsClearAction: showsClearAction,
                canClear: holdsCurrentTabs,
                clear: { _ = context.tabActions.clearCurrentTabs() }
            )
        }
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
        lhs.context == rhs.context && lhs.showsClearAction == rhs.showsClearAction
    }
}
