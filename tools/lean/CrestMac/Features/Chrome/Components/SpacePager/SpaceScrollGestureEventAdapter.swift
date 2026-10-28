import AppKit
import SwiftUI

/// Keeps AppKit phase, delta conventions, and event consumption at the native boundary.
@MainActor
final class SpaceScrollGestureEventAdapter {
    private var recognizer = SpaceScrollGestureRecognizer()

    func reset() {
        recognizer.reset()
    }

    func cancelCurrentGesture() {
        recognizer.cancelCurrentGesture()
    }

    func handle(
        _ event: NSEvent, isInside: Bool, layoutDirection: LayoutDirection,
        isEnabled: Bool = true,
        onStep: (BrowserSpaceSwipeDirection) -> Void
    ) -> NSEvent? {
        if !isEnabled { recognizer.cancelCurrentGesture() }
        let decision = recognizer.consume(
            Self.input(for: event, layoutDirection: layoutDirection), isInside: isInside && isEnabled)
        guard isEnabled else { return event }
        if let direction = decision.direction { onStep(direction) }
        return decision.consumesEvent ? nil : event
    }

    static func input(for event: NSEvent, layoutDirection: LayoutDirection) -> SpaceScrollGestureRecognizer.Input {
        let phase: SpaceScrollGestureRecognizer.Phase
        if event.phase.contains(.cancelled) {
            phase = .cancelled
        } else if event.phase.contains(.ended) {
            phase = .ended
        } else if event.phase.contains(.began) {
            phase = .began
        } else if event.phase.contains(.mayBegin) {
            phase = .mayBegin
        } else if !event.phase.isEmpty {
            phase = .changed
        } else {
            phase = .none
        }
        return .init(
            deltaX: layoutDirection.semanticHorizontalTranslation(event.scrollingDeltaX),
            deltaY: event.scrollingDeltaY,
            timestamp: event.timestamp,
            isPrecise: event.hasPreciseScrollingDeltas,
            phase: phase,
            isMomentum: !event.momentumPhase.isEmpty
        )
    }
}
