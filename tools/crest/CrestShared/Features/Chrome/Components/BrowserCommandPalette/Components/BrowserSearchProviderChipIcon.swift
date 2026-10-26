import SwiftUI

/// A search provider's logo as a chip wears it: on a neutral paper plate, so
/// a logo in its own brand color still reads on glass tinted with that color.
/// The plate is light in either appearance, so the logo draws as it would on
/// a light page. A locked Space fetches no icon and shows the provider's
/// kind instead.
struct BrowserSearchProviderChipIcon: View {
    let provider: SearchProvider
    var profileID: UUID? = nil

    @Environment(\.browserSpaceContentIsLocked) private var isLocked

    var body: some View {
        let plate = BrowserCommandPaletteMetrics.chipIconPlateSize
        BrowserSearchProviderIcon(
            provider: provider, profileID: isLocked ? nil : profileID, size: BrowserCommandPaletteMetrics.chipIconSize
        )
        .frame(width: plate, height: plate)
        .background(CrestBrandPalette.paper, in: .circle)
        .environment(\.colorScheme, .light)
        .accessibilityHidden(true)
    }
}
