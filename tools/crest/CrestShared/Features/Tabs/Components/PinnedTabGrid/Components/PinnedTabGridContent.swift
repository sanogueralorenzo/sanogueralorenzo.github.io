import SwiftUI

struct PinnedTabGridContent: View {
    /// The width of the drop target that trails the last pinned tile.
    private static let trailingTargetWidth = CrestSpacing.extraLarge

    @Environment(BrowserSidebarInteractionState.self) private var sidebarInteraction: BrowserSidebarInteractionState?
    let grid: PinnedTabGrid

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tabs: [TabStateModel] { grid.tabs }
    private var assignment: BrowserSpaceRuntimeAssignment { grid.assignment }
    private var capabilities: BrowserInteractionCapabilities { grid.capabilities }

    private var reorderContext: BrowserSidebarReorderContext? {
        guard
            capabilities.supportsOrganization,
            let context = grid.context,
            let sidebarInteraction
        else { return nil }
        return BrowserSidebarReorderContext(
            browser: context.browser,
            state: sidebarInteraction.sidebarReorderState
        )
    }

    var body: some View {
        BrowserPinnedTabSlotLayout(projection: projection) {
            ForEach(tabs, id: \.id) { tab in
                PinnedTabTile(
                    tab: tab, grid: grid, reorder: reorderContext
                )
            }
            RoundedRectangle(cornerRadius: BrowserSidebarMetrics.layerCornerRadius(), style: .continuous)
                .fill(.primary.opacity(0.035))
                .overlay {
                    RoundedRectangle(cornerRadius: BrowserSidebarMetrics.layerCornerRadius(), style: .continuous)
                        .strokeBorder(.primary.opacity(0.12), lineWidth: 0.5)
                }
                .opacity(projection.insertionIndex == nil ? 0 : 1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .animation(
            CrestMotion.dragSource.unlessReducingMotion(reduceMotion),
            value: projection.slots
        )
        .environment(\.browserInteractionCapabilities, capabilities)
        .crestCollectionMotion(ids: tabs.map(\.id))
        .overlay(alignment: .trailing) {
            if reorderContext != nil, let dragState = grid.dragState, dragState.item != nil {
                Color.clear
                    .frame(width: Self.trailingTargetWidth)
                    .frame(maxHeight: .infinity)
                    .contentShape(.rect)
                    .accessibilityHidden(true)
            }
        }
    }

    private var projection: BrowserPinnedTabReorderLayout {
        let ids = tabs.map { BrowserSidebarReorderItemID.tab($0.id) }
        return (reorderContext?.state.pinnedLayout(ids: ids, in: assignment) ?? BrowserPinnedTabReorderLayout(ids: ids))
            .applyingPreferences(width: BrowserChromeLayout.sidebarIdealWidth, touch: capabilities.supportsTouch)
    }

}
