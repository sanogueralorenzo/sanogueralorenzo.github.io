import SwiftUI

/// Keeps the card mounted while sliding only its own region, as Crest does.
struct BrowserSidebarSurface: View {
    let store: BrowserStore
    let cornerRadius: CGFloat
    let height: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var regionWidth: CGFloat { store.sidebarWidth + SidebarGeometry.inset * 2 }

    var body: some View {
        BrowserSidebar(store: store, cornerRadius: cornerRadius)
            .frame(height: max(0, height - SidebarGeometry.inset * 2))
            .compositingGroup()
            .shadow(
                color: .black.opacity(reduceTransparency || !store.showsSidebar ? 0 : 0.3),
                radius: 28, x: 8, y: 8
            )
            .padding(SidebarGeometry.inset)
            .frame(width: regionWidth)
            .background {
                if store.showsSidebar { BrowserWindowTitleBarSurface().accessibilityHidden(true) }
            }
            .contentShape(.interaction, Rectangle())
            .overlay {
                if store.showsSidebar {
                    BrowserSidebarHoverTracker(isRevealedByPointer: store.sidebarRevealed) { inside in
                        withAnimation(LeanMotion.floatingPane.unlessReducingMotion(reduceMotion)) {
                            store.sidebarRevealed = inside
                        }
                    }
                    .padding(SidebarGeometry.inset - SidebarGeometry.hoverMargin)
                    .accessibilityHidden(true)
                }
            }
            .offset(x: store.showsSidebar ? 0 : -regionWidth)
            .allowsHitTesting(store.showsSidebar)
            .accessibilityHidden(!store.showsSidebar)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
