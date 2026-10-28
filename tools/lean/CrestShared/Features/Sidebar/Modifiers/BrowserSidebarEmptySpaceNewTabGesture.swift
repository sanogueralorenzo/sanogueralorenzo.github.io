import SwiftUI

/// Attach only to the unoccupied remainder below the tab list. Keeping the
/// gesture off the scroll view leaves rows, drop bands, and controls untouched.
struct BrowserSidebarEmptySpaceNewTabGesture: ViewModifier {
    let tabActions: BrowserSidebarTabActions
    let openNewTab: () -> Void

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            TapGesture(count: 2).onEnded {
                tabActions.openNewTab(openNewTab)
            }
        )
    }
}
