import CoreGraphics

/// The fixed geometry every split-view column surface agrees on.
///
/// Both platforms lay cards out with these numbers, and the pure arithmetic in
/// `BrowserSplitColumnLayout` takes them as defaults, so a card measured in the
/// layout manager and a card measured in a test are the same card.
enum BrowserSplitLayoutMetrics {
    /// The space between two cards.
    ///
    /// It is the inset the window content surface already keeps around a single
    /// page, so a split window reads as one evenly inset surface rather than as
    /// crowded neighbours. The gap is also where the resize affordance lives —
    /// a card is never covered by the control that resizes it.
    static let interCardGap = BrowserChromeLayout.pageFrameInset

    /// The narrowest a card ever becomes.
    ///
    /// Resizing floors here, and a window too narrow for its cards clips rather
    /// than dissolving the group: layout never destroys membership.
    static let minimumCardWidth: CGFloat = 240

    /// How far the resize affordance reaches past the gap on each side, so the
    /// divider is grabbable without swallowing the card edges behind it.
    static let resizeHandleOverhang: CGFloat = 4

    /// The pointer target for one divider: the gap plus a symmetric overhang.
    ///
    /// This lands on the same width as `BrowserSidebarResizeHandleMetrics`,
    /// which keeps both of Crest's resize affordances feeling identical under
    /// the pointer.
    static let resizeHandleHitWidth = interCardGap + resizeHandleOverhang * 2

    /// Resting cards share the row's ordinary drawing plane.
    static let restingCardZIndex: Double = 0

    /// The card browser chrome speaks for crosses above its siblings while the
    /// row changes order, preserving the sense that it is the card being moved.
    static let focusedCardZIndex: Double = 1
}
