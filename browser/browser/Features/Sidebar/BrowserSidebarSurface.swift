import SwiftUI

/// Keep the card mounted during its slide, as in Crest.
struct BrowserSidebarSurface: View {
    let store: BrowserStore
    let height: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var regionWidth: CGFloat { store.sidebarWidth + SidebarGeometry.inset * 2 }

    var body: some View {
        BrowserSidebar(store: store)
            .frame(height: max(0, height - SidebarGeometry.inset * 2))
            .compositingGroup()
            .shadow(
                color: .black.opacity(reduceTransparency || !store.showsSidebar ? 0 : 0.3),
                radius: 12, x: 2, y: 5
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
                        // A tracker still sliding out cannot start another reveal.
                        guard !inside || store.showsSidebar else { return }
                        withAnimation(BrowserMotion.floatingPane.unlessReducingMotion(reduceMotion)) {
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

extension View {
    func browserSidebarPanel() -> some View {
        let shape = RoundedRectangle(cornerRadius: SidebarGeometry.panelRadius)
        return background(BrowserBrandTheme.surface, in: shape)
            .clipShape(shape)
            .overlay { shape.strokeBorder(BrowserBrandTheme.line, lineWidth: 0.75).allowsHitTesting(false) }
    }
}
