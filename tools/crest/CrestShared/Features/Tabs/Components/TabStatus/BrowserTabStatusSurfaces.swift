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

    @State private var iconPalette: BrowserFaviconPalette?

    var body: some View {
        if let tab {
            let marks = BrowserTabStatus.marks(of: tab)
            let surfaces = marks.compactMap(\.surface)
            let outline = marks.first { $0.surface?.outlineWidth != nil }
            let shape = RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
            let drawsEqualizer =
                surfaces.contains(where: \.drawsEqualizer)
                && BrowserDeviceAppearanceStore.shared.tabs.showsAudioVisualizer
            ZStack {
                if drawsEqualizer {
                    BrowserTabEqualizer(
                        color: barColor(of: tab).opacity(style.barOpacity), spectrum: tab.audioSpectrum
                    )
                    .clipShape(shape)
                }
                if let outline, let width = outline.surface?.outlineWidth {
                    shape.strokeBorder(outline.tint, lineWidth: width)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .task(id: drawsEqualizer ? tab.favicon?.identity : nil) {
                guard drawsEqualizer, let favicon = tab.favicon else { return }
                let palette = await BrowserFaviconPaletteLoader.shared.palette(for: favicon.data)
                guard !Task.isCancelled else { return }
                iconPalette = palette
            }
        }
    }

    // MARK: - Actions - Color

    private func barColor(of tab: BrowserTabStatusSource) -> Color {
        (tab.siteTheme?.preferring(extracted: iconPalette?.primary.iconAccent) ?? iconPalette?.primary.iconAccent)?
            .color ?? style.accent
    }
}
