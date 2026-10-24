import SwiftUI

struct BrowserSiteExtensionActionButton: View {
    let action: BrowserExtensionActionPresentation
    let perform: (BrowserExtensionPopupAnchor?) -> Void
    let togglePinned: () -> Void
    var presentMenu: (BrowserExtensionPopupAnchor?) -> Void = { _ in }

    @State private var isHovering = false
    @State private var popupAnchor: BrowserExtensionPopupAnchor?

    var body: some View {
        anchoredButton
            .contentShape(.rect)
            .onHover { isHovering = $0 }
    }

    private var anchoredButton: some View {
        actionSurface
            .frame(maxWidth: .infinity)
            .background {
                BrowserExtensionPopupAnchorReader(popupAnchor: $popupAnchor)
            }
    }

    private var actionSurface: some View {
        ZStack(alignment: .bottomTrailing) {
            actionButton
            BrowserExtensionPinButton(
                isPinned: action.isPinned,
                action: togglePinned
            )
            .opacity(isHovering ? 1 : 0)
            .allowsHitTesting(isHovering)
            .offset(x: 3, y: 3)
        }
    }

    private var actionButton: some View {
        BrowserSiteExtensionActionControl(
            action: action,
            perform: { perform(popupAnchor) },
            togglePinned: togglePinned,
            presentMenu: presentMenu
        )
    }
}
