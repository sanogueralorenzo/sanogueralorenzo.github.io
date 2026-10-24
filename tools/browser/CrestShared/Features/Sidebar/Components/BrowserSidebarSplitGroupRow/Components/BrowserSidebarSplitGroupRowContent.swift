import SwiftUI

/// Shared tab rows inside the group's frame; each member can be dragged out.
struct BrowserSidebarSplitGroupRowContent: View {
    let configuration: BrowserSidebarSplitGroupRowConfiguration
    let interaction: BrowserSidebarSplitGroupRowInteractionContext

    @Environment(\.sidebarLayerDepth) private var depth
    @AppStorage(BrowserSidebarDensityPreference.scaleKey, store: BrowserSidebarDensityPreference.defaults)
    private var tabScale = 1.0

    var body: some View {
        VStack(spacing: configuration.metrics.memberSpacing) {
            BrowserSidebarSplitGroupHeader(
                configuration: configuration,
                interaction: interaction
            )

            // Each member keeps its own identity: selecting one prepositions
            // the sidebar's scroll onto the row the page will zoom from, and a
            // group whose rows shared one identity would scroll to the wrong
            // place — or to nowhere at all.
            ForEach(configuration.members, id: \.id) { member in
                BrowserSidebarTabRow(tab: member, context: configuration.context, isSplitGroupMember: true)
                    .equatable()
                    .id(member.id)
            }
        }
        .environment(\.sidebarLayerDepth, depth + 1)
        .padding([.horizontal, .top], BrowserSidebarMetrics.containerPadding)
        .padding(.bottom, BrowserSidebarMetrics.containerBottomPadding(tabScale: tabScale))
    }
}
