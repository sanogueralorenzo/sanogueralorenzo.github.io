import SwiftUI

/// The compact shell's scrolling chrome around the shared tab list.
///
/// What belongs to this shell rather than to the list is the prepositioning: the
/// page a row opens grows out of that row in place, so the row has to be on
/// screen with a real resting frame before the morph starts. The lists are lazy,
/// and scrolling to the shown tab's row by its identity makes that row before
/// the morph reads its frame.
struct MobileBrowserSpaceTabListScroll<Content: View>: View {
    @Environment(BrowserSidebarInteractionState.self) private var sidebarInteraction

    let context: BrowserSidebarListContext
    let compactPageIsFullyPresented: Bool
    let openNewTab: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        LazyVStack(spacing: 0) {
                            content()
                        }
                        .sidebarScrollContent()
                        .padding(.bottom, 8)

                        Color.clear
                            .contentShape(.rect)
                            .modifier(
                                BrowserSidebarEmptySpaceNewTabGesture(
                                    tabActions: context.tabActions,
                                    openNewTab: openNewTab
                                )
                            )
                            .accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: geometry.size.height, alignment: .top)
                }
                .modifier(SidebarScrollAffordance(isDragging: sidebarInteraction.sidebarReorderState.isDragging))
                .scrollClipDisabled(
                    !BrowserSidebarReorderVisuals.clipsScrollableRegion(
                        clipsWhenIdle: BrowserSidebarReorderVisuals.clipsScrollableRegionWhenIdle,
                        isDragging: sidebarInteraction.sidebarReorderState.isDragging
                    )
                )
                .simultaneousGesture(
                    TapGesture().onEnded {
                        BrowserAddressFocusDismissal.dismiss()
                    }
                )
                .accessibilityLabel("Saved and current tabs")
                .accessibilityIdentifier(
                    BrowserSpaceAccessibilityID.tabs(context.space.id)
                )
                .onChange(of: selectedPromotionTarget) { previous, current in
                    guard compactPageIsFullyPresented, let current, previous != current
                    else { return }

                    var transaction = Transaction(animation: nil)
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        proxy.scrollTo(current.tabID, anchor: .center)
                    }
                }
            }
        }
    }

    /// Where the page the window shows would grow out of, which reads only the
    /// Space's shown tab, not any list.
    private var selectedPromotionTarget: MobileTabPromotionTarget? {
        let spaceID = context.space.id
        guard let tabID = context.window.shownTabs.first(where: { $0.spaceID == spaceID })?.tabID,
            let tab = context.space.tabs.model(tabID)
        else { return nil }
        return MobileTabPromotionTarget(shownTab: tab)
    }
}
