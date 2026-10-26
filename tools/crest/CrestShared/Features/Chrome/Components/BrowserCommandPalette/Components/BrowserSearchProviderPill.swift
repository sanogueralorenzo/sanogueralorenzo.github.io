import SwiftUI

/// A search provider's chip: its icon on a neutral plate and its name, on
/// glass in its brand color, which the palette's glow repeats.
struct BrowserSearchProviderPill: View {
    let provider: SearchProvider
    var showsCloseControl = false
    var isInteractive = false
    var profileID: UUID? = nil

    var body: some View {
        BrowserPaletteChip(
            color: provider.color.color, showsCloseControl: showsCloseControl, isInteractive: isInteractive
        ) {
            BrowserSearchProviderChipIcon(provider: provider, profileID: profileID)
            Text(verbatim: provider.title)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
        }
    }
}
