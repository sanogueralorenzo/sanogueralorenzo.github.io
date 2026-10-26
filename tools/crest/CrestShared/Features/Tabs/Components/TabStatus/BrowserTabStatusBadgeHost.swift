import SwiftUI

// MARK: - Types

/// Where a tab's favicon sits, so the row or tile drawing it can hang a status
/// badge off its corner from above its own gestures.
struct TabFaviconBoundsKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

extension EnvironmentValues {
    /// Whether a status badge has taken the corner a tab's favicon gives its
    /// engine badge, so the engine badge steps aside.
    @Entry var tabFaviconBadgeIsTaken = false

    /// Whether a status shows in place of a tab's favicon, so the favicon
    /// steps aside.
    @Entry var tabFaviconIsReplaced = false
}

/// Shows the first status a tab's page is in, in the order the statuses list
/// them, as the person chose: beside the tab's favicon where its `anchor`
/// puts it, or in place of the favicon itself. Either way it sits above the
/// row's or tile's gestures, menu and accessibility, so pressing it only does
/// what it says: a quick second press never restores a saved page, and a
/// middle click never unloads the tab.
struct BrowserTabStatusBadgeHost: ViewModifier {
    // MARK: - Variables

    /// The tab's page, where the host can read it.
    let tab: BrowserTabStatusSource?

    /// Where the badge hangs when it sits beside the favicon.
    var anchor = BrowserTabStatusBadgeAnchor.favicon

    private var iconScale: Double { BrowserDeviceAppearanceStore.shared.tabScale }

    func body(content: Content) -> some View {
        let mark = tab.flatMap { BrowserTabStatus.marks(of: $0).first }
        let replacesIcon = BrowserDeviceAppearanceStore.shared.tabs.statusStyle == .icon
        content
            .environment(\.tabFaviconBadgeIsTaken, mark != nil && !replacesIcon && anchor.takesFaviconCorner)
            .environment(\.tabFaviconIsReplaced, mark != nil && replacesIcon)
            .overlayPreferenceValue(TabFaviconBoundsKey.self) { iconBounds in
                if let iconBounds, let mark, let tab {
                    GeometryReader { proxy in
                        let icon = proxy[iconBounds]
                        let scale = BrowserSidebarDensity(iconScale).scale
                        if replacesIcon {
                            BrowserTabStatusBadge(mark: mark, tab: tab, diameter: min(icon.width, icon.height))
                                .position(x: icon.midX, y: icon.midY)
                        } else {
                            let diameter = BrowserTabStatusBadge.diameter * scale
                            BrowserTabStatusBadge(mark: mark, tab: tab, diameter: diameter)
                                .position(
                                    anchor.center(
                                        icon, proxy.size, diameter, scale, BrowserSidebarMetrics.layerCornerRadius()))
                        }
                    }
                }
            }
    }
}
