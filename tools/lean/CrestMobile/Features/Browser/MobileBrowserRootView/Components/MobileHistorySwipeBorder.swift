import SwiftUI

/// The frame around a page, where a swipe in toward the page steps its history
/// as one that starts on the page's own edge does: in from the leading side
/// goes back, from the trailing side forward. A finger reaching for the edge
/// of the screen lands here rather than on the page.
struct MobileHistorySwipeBorder: View {
    let insets: EdgeInsets
    /// The page beside the frame's leading side.
    let leadingPage: MobileBrowserPage?
    /// The page beside the frame's trailing side.
    let trailingPage: MobileBrowserPage?

    var body: some View {
        HStack(spacing: 0) {
            if insets.leading > 0, let leadingPage {
                MobileHistorySwipeBorderSide(page: leadingPage, direction: .back)
                    .frame(width: insets.leading)
            }
            Spacer(minLength: 0)
            if insets.trailing > 0, let trailingPage {
                MobileHistorySwipeBorderSide(page: trailingPage, direction: .forward)
                    .frame(width: insets.trailing)
            }
        }
    }
}
