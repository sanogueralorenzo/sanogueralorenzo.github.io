import SwiftUI

/// Makes the frame a bordered window draws around its pages act as the
/// window's title bar (`BrowserWindowTitleBarSurface`) along every edge, as
/// the sidebar's empty space and the strip above the page already do.
///
/// A Space's pages are hosted in a view that spans the frame as well as the
/// pages, so the backdrop's surface behind it never sees a press there. These
/// strips cover the frame alone. A borderless window has no frame, and its
/// pages keep every press up to the window's edge.
struct BrowserPageFrameTitleBarSurface: View {
    let insets: EdgeInsets

    var body: some View {
        Color.clear
            .overlay(alignment: .top) { strip(insets.top).frame(height: insets.top) }
            .overlay(alignment: .bottom) { strip(insets.bottom).frame(height: insets.bottom) }
            .overlay(alignment: .leading) { strip(insets.leading).frame(width: insets.leading) }
            .overlay(alignment: .trailing) { strip(insets.trailing).frame(width: insets.trailing) }
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func strip(_ thickness: CGFloat) -> some View {
        if thickness > 0 {
            BrowserWindowTitleBarSurface()
        }
    }
}
