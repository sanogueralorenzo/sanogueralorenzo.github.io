import SwiftUI

struct BrowserSiteExtensionActionLabel: View {
    let action: BrowserExtensionActionPresentation

    var body: some View {
        BrowserExtensionActionArtwork(
            action: action,
            glyphSize: BrowserSiteControlMetrics.extensionGlyphSize
        )
        .frame(maxWidth: .infinity)
        .frame(height: BrowserSiteControlMetrics.extensionActionHeight)
        .contentShape(.rect)
    }
}
