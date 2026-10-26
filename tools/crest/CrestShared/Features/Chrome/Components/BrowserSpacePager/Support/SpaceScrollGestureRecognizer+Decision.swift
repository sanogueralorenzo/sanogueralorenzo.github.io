import Foundation

extension SpaceScrollGestureRecognizer {
    /// What the recognizer makes of one scroll event: whether the event is the
    /// Space swipe's, and the Space it steps to, if it completes a step.
    struct Decision: Equatable {
        // MARK: - Static Variables

        /// The event is not a Space swipe, so it scrolls what it is over.
        static let passThrough = Decision(consumesEvent: false, direction: nil)
        /// The event belongs to a Space swipe and steps nowhere.
        static let consumed = Decision(consumesEvent: true, direction: nil)

        // MARK: - Variables

        let consumesEvent: Bool
        /// The direction of the Space the event steps to.
        let direction: BrowserSpaceSwipeDirection?

        // MARK: - Actions - Decisions

        /// The event completes a swipe to the Space in `direction`.
        static func step(_ direction: BrowserSpaceSwipeDirection) -> Decision {
            Decision(consumesEvent: true, direction: direction)
        }
    }
}
