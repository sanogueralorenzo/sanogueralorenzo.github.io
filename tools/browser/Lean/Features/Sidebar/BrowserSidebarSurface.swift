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
            .animation(nil, value: store.showsSidebar)
            .frame(height: max(0, height - SidebarGeometry.inset * 2))
            .compositingGroup()
            .shadow(
                color: .black.opacity(reduceTransparency || !store.showsSidebar ? 0 : 0.3),
                radius: 28, x: 8, y: 8)
            .padding(SidebarGeometry.inset)
            .frame(width: regionWidth)
            .overlay {
                if store.showsSidebar {
                    BrowserSidebarHoverTracker(isRevealedByPointer: store.sidebarRevealed) { inside in
                        store.sidebarRevealed = inside
                    }
                    .padding(SidebarGeometry.inset - SidebarGeometry.hoverMargin)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .offset(x: store.showsSidebar ? 0 : -regionWidth)
            .allowsHitTesting(store.showsSidebar)
            .accessibilityHidden(!store.showsSidebar)
            .animation(reduceMotion ? nil : .smooth(duration: 0.24), value: store.showsSidebar)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
