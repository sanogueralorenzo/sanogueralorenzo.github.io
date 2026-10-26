import SwiftUI

/// The sample page at the chosen default zoom, for the Page card when the pane
/// has no pinned window crop to show it in.
struct BrowserLookAndFeelPagePreview: View {
    private var pageZoom = BrowserDefaultPageZoomStore.shared

    var body: some View {
        BrowserSettingsPagePreview(zoom: pageZoom.defaultZoom)
            .clipShape(.rect(cornerRadius: CrestRadius.compact, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: CrestRadius.compact, style: .continuous)
                    .strokeBorder(.primary.opacity(CrestOpacity.border))
            }
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("default-page-zoom-preview")
    }
}
