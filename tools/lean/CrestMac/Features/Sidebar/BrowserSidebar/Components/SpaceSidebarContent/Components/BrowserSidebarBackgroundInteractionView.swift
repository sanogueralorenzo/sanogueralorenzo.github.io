import SwiftUI

struct BrowserSidebarBackgroundInteractionView: View {
    var body: some View {
        // Dragging the empty sidebar moves the window. Its double-click opens a
        // new tab (`BrowserSidebarEmptySpaceNewTabGesture`) rather than acting
        // as the title bar, as it has since Crest offered it.
        Color.clear
            .contentShape(.rect)
            .gesture(WindowDragGesture())
            .allowsWindowActivationEvents()
            .accessibilityLabel("Sidebar background")
            .accessibilityHint("Drag to move the window")
    }
}
