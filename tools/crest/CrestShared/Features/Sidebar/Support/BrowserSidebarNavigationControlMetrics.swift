import SwiftUI

/// The drawn geometry of the sidebar's navigation strip, resolved once per
/// shell rather than spelled out by each fork of the strip.
///
/// The strip holds the same three controls everywhere — back, forward, and
/// reload — and what changes between shells is only how big they are, how far
/// apart, and how far the row is held off the sidebar's edges.
struct BrowserSidebarNavigationControlMetrics: Equatable, Sendable {
    /// The gap between adjacent controls.
    let controlSpacing: CGFloat

    /// The gap the leading spacer will not compress below, which is what keeps
    /// the strip clear of whatever sits to its left.
    let leadingSpacerMinimum: CGFloat

    /// The hit target each control claims.
    let controlSize: CGSize

    /// The narrow chevron beside the reload control that opens the developer
    /// reload menu. It is deliberately narrower than a full target: it sits
    /// flush against reload and the two read as one control.
    let reloadMenuControlSize: CGSize

    /// The back and forward chevrons' own font.
    let historySymbolFont: Font

    /// The reload glyph's point size, which the reload control turns into its
    /// own font so the spin animation stays centered.
    let reloadSymbolPointSize: CGFloat

    let leadingInset: CGFloat

    let trailingInset: CGFloat

    /// The band the strip occupies, read together with `growsWithContent`.
    let barHeight: CGFloat

    /// Whether `barHeight` is a floor the strip may grow past.
    ///
    /// A pointer shell pins the strip: it stands in for the window's titlebar
    /// and has to line up with the system's own controls beside it. A touch
    /// shell has nothing to line up with and lets an accessibility text size
    /// push the row taller.
    let growsWithContent: Bool

    /// The breathing room added above and below once the reader has chosen an
    /// accessibility text size.
    let accessibilityVerticalPadding: CGFloat

    /// A pointer shell: compact targets in a titlebar-height strip, held off
    /// the sidebar's trailing edge.
    static let pointer = BrowserSidebarNavigationControlMetrics(
        controlSpacing: 1,
        leadingSpacerMinimum: CrestSpacing.small,
        controlSize: CGSize(
            width: BrowserChromeLayout.sidebarNavigationControlHitTarget,
            height: BrowserChromeLayout.sidebarNavigationControlHitTarget
        ),
        reloadMenuControlSize: CGSize(
            width: 18,
            height: BrowserChromeLayout.sidebarNavigationControlHitTarget
        ),
        historySymbolFont: .system(
            size: BrowserChromeLayout.sidebarNavigationSymbolPointSize,
            weight: .regular
        ),
        reloadSymbolPointSize: BrowserChromeLayout
            .sidebarNavigationSymbolPointSize,
        leadingInset: 0,
        trailingInset: BrowserChromeLayout.sidebarNavigationTrailingInset,
        barHeight: BrowserChromeLayout.sidebarTitlebarHeight,
        growsWithContent: false,
        accessibilityVerticalPadding: 0
    )

    /// A touch shell: full 44pt targets, a symmetric gutter, and a strip that
    /// grows with the reader's text.
    ///
    /// The targets are literals rather than `CrestLayout.minimumHitTarget`, for
    /// the same reason the touch trailing control's are: this profile is
    /// compared against from a suite hosted on macOS, where that token resolves
    /// to the pointer shell's 28, and a touch control still has to be 44.
    static let touch = BrowserSidebarNavigationControlMetrics(
        controlSpacing: 2,
        leadingSpacerMinimum: 0,
        controlSize: CGSize(width: 44, height: 44),
        reloadMenuControlSize: CGSize(width: 28, height: 44),
        historySymbolFont: .system(size: 17, weight: .medium),
        reloadSymbolPointSize: BrowserChromeSymbolLabel.defaultPointSize,
        leadingInset: 14,
        trailingInset: 14,
        barHeight: 48,
        growsWithContent: true,
        accessibilityVerticalPadding: 8
    )
}
