import SwiftUI

/// The start page's column: the header, then the palette.
struct BrowserStartPageStack: View {
    let page: BrowserStartPage

    var body: some View {
        VStack(spacing: page.layout.spacing) {
            BrowserStartPageHeader(
                isPrivateBrowsing: page.isPrivateBrowsing,
                layout: page.layout,
                colorScheme: page.headerColorScheme
            )
            BrowserStartPageCommandPalette(page: page)
        }
        .padding(page.layout.padding)
        .frame(maxWidth: page.layout.maximumWidth)
    }
}
