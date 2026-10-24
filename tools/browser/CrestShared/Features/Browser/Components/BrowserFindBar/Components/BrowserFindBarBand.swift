import SwiftUI

/// The band the find bar occupies: an exact height where the bar is a panel
/// floating over the page, a floor where it is chrome that may grow with the
/// reader's text.
struct BrowserFindBarBand: ViewModifier {
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
