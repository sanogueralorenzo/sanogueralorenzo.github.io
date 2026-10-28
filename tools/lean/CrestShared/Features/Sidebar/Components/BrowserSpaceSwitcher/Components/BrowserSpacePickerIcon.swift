import SwiftUI

/// One Space's color dot, sized for the switcher's input surface.
struct BrowserSpacePickerIcon: View {
    let space: BrowserSpaceIdentity
    let metrics: BrowserSpacePickerMetrics

    var body: some View {
        BrowserSpaceIdentityIcon(
            identity: space,
            size: metrics.iconSize
        )
        .padding(metrics.iconPadding)
    }
}
