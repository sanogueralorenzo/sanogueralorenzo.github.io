import SwiftUI

/// One Space's crest as the switcher draws it.
///
/// The shared artwork preserves the crest's original colors and layered badge
/// in both the compact desktop track and the expanded touch segments.
struct BrowserSpacePickerIcon: View {
    let space: BrowserSpaceIdentity
    let metrics: BrowserSpacePickerMetrics

    var body: some View {
        BrowserSpaceSymbolArtwork(
            identity: space,
            size: metrics.iconSize,
            lockSize: metrics.lockSize
        )
        .padding(metrics.iconPadding)
    }
}
