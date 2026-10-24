import SwiftUI

/// A tab row's favicon, in whatever column the shell reserves for it.
struct BrowserSidebarTabFavicon: View {
    let tab: TabStateModel
    let favicons: FaviconAssets
    let profileID: UUID
    let metrics: BrowserSidebarTabRowMetrics
    /// Whether the icon carries the row's selection, which is the one state
    /// that earns full-strength ink.
    var isProminent = false
    var isLoaded = true
    @AppStorage(BrowserSidebarDensityPreference.scaleKey, store: BrowserSidebarDensityPreference.defaults) private
        var iconScale = 1.0

    var body: some View {
        BrowserSidebarTabFaviconContent(
            tab: tab, favicons: favicons, profileID: profileID, metrics: metrics, isProminent: isProminent,
            isLoaded: isLoaded, iconScale: iconScale
        )
    }
}
