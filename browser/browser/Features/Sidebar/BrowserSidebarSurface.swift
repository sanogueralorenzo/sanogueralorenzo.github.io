import SwiftUI

struct BrowserSidebarSurface: View, Animatable {
    let store: BrowserStore
    let height: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.layoutDirection) private var layoutDirection
    var animatableData: CGFloat

    init(store: BrowserStore, height: CGFloat) {
        self.store = store
        self.height = height
        animatableData = store.showsSidebar ? 1 : 0
    }

    var body: some View {
        let progress = min(max(animatableData, 0), 1)
        let offset = (progress - 1) * store.sidebarRegionWidth
        let left: Alignment = layoutDirection == .leftToRight ? .topLeading : .topTrailing
        BrowserSidebar(store: store)
            .frame(height: max(0, height - SidebarGeometry.inset * 2))
            .compositingGroup()
            .shadow(
                color: .black.opacity(reduceTransparency ? 0 : 0.24 * progress),
                radius: 12, x: 2, y: 4
            )
            .padding(SidebarGeometry.inset)
            .offset(x: offset)
            .allowsHitTesting(store.showsSidebar)
            .accessibilityHidden(!store.showsSidebar)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: left)
            .overlay(alignment: left) {
                if store.showsSidebar {
                    BrowserSidebarHoverTracker(waitsForPointer: store.utility != nil && !store.sidebarDocked) {
                        inside in
                        guard store.showsSidebar, store.sidebarRevealed != inside else { return }
                        store.sidebarRevealed = inside
                    }
                    .frame(width: store.sidebarWidth + SidebarGeometry.inset, height: height)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                } else {
                    BrowserCollapsedSidebarHoverTracker { inside in
                        guard inside, !store.showsSidebar, store.window?.isKeyWindow == true else { return }
                        store.sidebarRevealed = true
                    }
                    .frame(width: SidebarGeometry.revealWidth, height: height)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .background(BrowserNativeWindowControlsBridge(sidebarOffset: offset))
    }
}
