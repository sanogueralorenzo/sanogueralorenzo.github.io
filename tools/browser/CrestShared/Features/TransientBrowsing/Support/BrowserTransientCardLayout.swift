import SwiftUI

/// The arithmetic a transient overlay's card shares wherever it is presented.
///
/// Peek and Quick Window both begin as a link under a pointer or a finger and
/// both grow into a card that has to stay inside whatever room the screen
/// leaves them. Neither sum depends on which shell is asking, so both live
/// here rather than once per platform.
enum BrowserTransientCardLayout {
    /// The transform that starts a card at the link it was opened from.
    ///
    /// The clamps keep a card recognisable: a link narrower than the lower
    /// bound would start as a hairline, and one wider than the upper bound
    /// would barely appear to grow at all.
    static func sourceCardTransform(
        for source: BrowserPeekSourcePresentation
    ) -> BrowserTransientSourceTransform {
        BrowserTransientSourceTransform(
            anchor: UnitPoint(
                x: source.normalizedTouchX,
                y: source.normalizedTouchY
            ),
            scaleX: min(max(source.normalizedWidth, 0.06), 0.42),
            scaleY: min(max(source.normalizedHeight, 0.035), 0.24)
        )
    }

    /// Insets that clear the screen's own safe area without letting a card
    /// press against the bezel on the edges where that area is thin.
    static func cardInsets(
        safeAreaInsets: EdgeInsets,
        minimumHorizontal: CGFloat,
        minimumVertical: CGFloat
    ) -> EdgeInsets {
        EdgeInsets(
            top: max(safeAreaInsets.top, minimumVertical),
            leading: max(safeAreaInsets.leading, minimumHorizontal),
            bottom: max(safeAreaInsets.bottom, minimumVertical),
            trailing: max(safeAreaInsets.trailing, minimumHorizontal)
        )
    }
}

/// The scale and anchor that place a transient card over its source link.
struct BrowserTransientSourceTransform: Equatable, Sendable {
    let anchor: UnitPoint
    let scaleX: CGFloat
    let scaleY: CGFloat
}
