import SwiftUI

struct BrowserSidebarBackgroundInteractionView: View {
    let editSpace: () -> Void
    let createSpace: (() -> Void)?

    var body: some View {
        // Dragging the empty sidebar moves the window. Its double-click opens a
        // new tab (`BrowserSidebarEmptySpaceNewTabGesture`) rather than acting
        // as the title bar, as it has since Crest offered it.
        Color.clear
            .contentShape(.rect)
            .gesture(WindowDragGesture())
            .allowsWindowActivationEvents()
            .contextMenu {
                ForEach(
                    BrowserSidebarBackgroundAction.all.filter {
                        !$0.requiresSpaceCreation || createSpace != nil
                    }
                ) { action in
                    Button(action.title, systemImage: action.symbol) {
                        action.perform(on: self)
                    }
                }
                .crestMenuActionLabelStyle()
            }
            .accessibilityLabel("Sidebar background")
            .accessibilityHint("Drag to move the window or open Space actions")
    }
}
