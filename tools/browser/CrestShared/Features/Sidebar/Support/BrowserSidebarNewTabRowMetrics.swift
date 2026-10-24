import CoreGraphics

/// The drawn geometry of the sidebar's new-tab row, resolved once per shell
/// rather than spelled out by the row.
///
/// The row is a control before it is a label, so what separates the two shells
/// is where its insets sit and how its height is decided. A pointer shell keeps
/// the row at one exact height and reveals a hover surface under it; a touch
/// shell lets the row grow with its label and has no hover to respond to.
struct BrowserSidebarNewTabRowMetrics: Equatable, Sendable {
    /// The inset between the row's own leading edge and its label.
    ///
    /// It belongs to the button rather than to the row, so the strip a reader
    /// aims at when they mean "new tab" reaches the edge of the surface instead
    /// of stopping short of it.
    let labelHorizontalInset: CGFloat

    /// Whether the row holds one exact height.
    ///
    /// A pointer shell keeps every row on one rhythm so the list reads as a
    /// scannable column. A touch row is already a hit target sized for a finger,
    /// so it takes a floor instead and grows with the label rather than
    /// clipping it — see `BrowserInteractionCapabilities.rowMinHeight`.
    let usesFixedHeight: Bool

    /// Whether the row wears the chrome's hover treatment.
    ///
    /// That treatment answers a pointer resting on the row, which is exactly
    /// what a touch shell has no way to show.
    let showsHoverSurface: Bool

    /// Whether the row carries its keyboard shortcut as a tooltip.
    ///
    /// A tooltip needs a pointer to rest still over the row before it appears,
    /// and the shortcut it names needs a keyboard to reach it.
    let showsShortcutTooltip: Bool

    /// A pointer shell: one exact row height, a hover surface, and the shortcut
    /// on hover.
    static let pointer = BrowserSidebarNewTabRowMetrics(
        labelHorizontalInset: 9,
        usesFixedHeight: true,
        showsHoverSurface: true,
        showsShortcutTooltip: true
    )

    /// A touch shell uses the same content margin as a tab row.
    static let touch = BrowserSidebarNewTabRowMetrics(
        labelHorizontalInset: BrowserSidebarTabRowMetrics.touch.contentLeadingInset,
        usesFixedHeight: false,
        showsHoverSurface: false,
        showsShortcutTooltip: false
    )
}
