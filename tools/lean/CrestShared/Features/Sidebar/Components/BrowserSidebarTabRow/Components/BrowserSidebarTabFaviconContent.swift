import SwiftUI

/// A tab row's favicon, in whatever column the shell reserves for it.
struct BrowserSidebarTabFaviconContent: View {
    let tab: TabStateModel
    let favicons: FaviconAssets
    let profileID: UUID
    let metrics: BrowserSidebarTabRowMetrics
    /// Whether the icon carries the row's selection, which is the one state
    /// that earns full-strength ink.
    var isProminent = false
    var isLoaded = true
    let iconScale: Double

    @Environment(\.tabFaviconIsReplaced) private var isReplaced

    var body: some View {
        TabStateFaviconView(
            tab: tab, favicons: favicons, profileID: profileID,
            size: TabFaviconMetrics.defaultSize * BrowserSidebarDensity(iconScale).scale
        )
        .opacity(isReplaced ? 0 : 1)
        .browserTabResidency(isLoaded: isLoaded)
        .overlay(alignment: .bottomTrailing) {
            TabEngineBadge(tabID: tab.id, scale: BrowserSidebarDensity(iconScale).scale)
        }
        .anchorPreference(key: TabFaviconBoundsKey.self, value: .bounds) { $0 }
        .modifier(BrowserSidebarTabFaviconColumn(slot: metrics.faviconSlot))
        .foregroundStyle(isProminent ? .primary : .secondary)
    }
}

/// Holds the favicon in a fixed column and sizes the symbol a tab falls back
/// to, where the shell asks for one.
private struct BrowserSidebarTabFaviconColumn: ViewModifier {
    let slot: BrowserSidebarTabFaviconSlot?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let slot {
            content
                .font(.system(size: slot.glyphSize, weight: slot.glyphWeight))
                .frame(width: slot.width)
        } else {
            content
        }
    }
}
