import SwiftUI

/// Which way on screen a person asked a split card to travel.
///
/// Everything below this type speaks in member order alone: the store and the
/// session take a signed offset, where `-1` is one slot toward the run's head.
/// The cards themselves are an `HStack` in member order, which SwiftUI mirrors
/// under a right-to-left layout — so in Arabic the head member draws on the
/// *right*, and "move left" has to mean `+1`.
///
/// Resolving the physical direction at the input boundary and leaving order
/// semantics everywhere else is the same shape `BrowserSpaceSwipeDirection` uses
/// to turn a swipe into a direction. The arrow chords bound to
/// these commands follow the label rather than the order: ⇧⌘← moves the card to
/// the person's left in both layouts.
enum BrowserSplitCardMoveDirection: Hashable, Sendable {
    case left
    case right

    func memberOffset(layoutDirection: LayoutDirection) -> Int {
        let towardHead: Self = layoutDirection == .leftToRight ? .left : .right
        return self == towardHead ? -1 : 1
    }
}
