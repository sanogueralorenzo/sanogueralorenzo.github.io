import SwiftUI

/// The band the navigation strip occupies: an exact height where the strip
/// stands in for a titlebar, a floor where it is free to grow with the reader's
/// text.
struct BrowserSidebarNavigationControlBand: ViewModifier {
    let height: CGFloat
    let growsWithContent: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if growsWithContent {
            content.frame(minHeight: height)
        } else {
            content.frame(height: height)
        }
    }
}
