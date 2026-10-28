import SwiftUI

/// The surfaces a tab's statuses dress it in, in the order the statuses list
/// them, for a row or tile to draw over its fill and under its content. An
/// outline takes the tint of the mark that draws it, so it says the same
/// thing as the badge.
///
/// Bars take the site's own color: the one the page declares, or the main
/// color of its icon for a page that declares none worth showing, and the
/// host's accent when neither has one. The icon's color is worked out only
/// while bars show, and the person can turn bars off in Look and Feel.
struct BrowserTabStatusSurfaces: View {
    // MARK: - Variables

    /// The tab's page, where the host can read it.
    let tab: BrowserTabStatusSource?
    let style: BrowserTabStatusSurfaceStyle

    var body: some View {
        if let tab, let outline = BrowserTabStatus.marks(of: tab).first(where: { $0.surface?.outlineWidth != nil }),
            let width = outline.surface?.outlineWidth
        {
            RoundedRectangle(cornerRadius: style.cornerRadius, style: .circular)
                .strokeBorder(CrestBrandTheme.accent, lineWidth: width)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
