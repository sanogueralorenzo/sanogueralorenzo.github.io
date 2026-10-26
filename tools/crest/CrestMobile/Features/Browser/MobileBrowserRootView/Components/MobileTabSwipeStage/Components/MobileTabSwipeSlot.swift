import SwiftUI

/// Places one page of the swipe stage, `place` tabs on from the shown one, as
/// far along as the swipe has moved it, and fades the shown one in where
/// Reduce Motion swapped it. Only this modifier reads the swipe's travel, so a
/// moving finger redraws the offsets and nothing beneath them.
struct MobileTabSwipeSlot: ViewModifier {
    let swipe: MobileTabSwipe
    let place: CGFloat

    func body(content: Content) -> some View {
        content
            .offset(x: swipe.offset(of: place))
            .opacity(place == 0 ? swipe.shownOpacity : 1)
    }
}
