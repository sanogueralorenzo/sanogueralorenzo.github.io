import SwiftUI

struct BrowserExtensionActionArtwork: View {
    let action: BrowserExtensionActionPresentation
    let glyphSize: CGFloat

    var body: some View {
        artwork
            .frame(width: glyphSize, height: glyphSize)
            .overlay(alignment: .topTrailing) {
                if !action.badgeText.isEmpty {
                    BrowserExtensionBadge(text: action.badgeText)
                }
            }
    }

    @ViewBuilder
    private var artwork: some View {
        if let icon = action.icon {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "puzzlepiece.extension.fill")
                .foregroundStyle(.secondary)
        }
    }
}
