import Foundation

/// Recognizes one horizontal Space intent without coupling selection to scroll position.
/// Phased gestures stay latched until their boundary; phase-less devices use a quiet gap
/// measured from the last event, never a timer measured from the last accepted step.
struct SpaceScrollGestureRecognizer {
    enum Phase: Equatable, Sendable {
        case none, mayBegin, began, changed, ended, cancelled
    }

    struct Input: Equatable, Sendable {
        let deltaX: CGFloat
        let deltaY: CGFloat
        let timestamp: TimeInterval
        let isPrecise: Bool
        let phase: Phase
        let isMomentum: Bool
    }

    private enum Axis {
        case undecided, horizontal, vertical, outside
    }

    // Precise deltas are points; ordinary wheel deltas are line units. These are
    // separate recognition thresholds, not a conversion tied to the tab-row height.
    private static let preciseThreshold: CGFloat = 40
    private static let wheelThreshold: CGFloat = 1
    private static let horizontalDominance: CGFloat = 1.35
    private static let phaseLessIdleInterval: TimeInterval = 0.35

    private var axis: Axis = .undecided
    private var accumulatedX: CGFloat = 0
    private var accumulatedY: CGFloat = 0
    private var initialDirection: CGFloat = 0
    private var hasResolved = false
    private var hasActivePhase = false
    private var hasFinished = false
    private var lastTimestamp: TimeInterval?

    mutating func reset() {
        self = Self()
    }

    /// Disabling recognition must reject the current stream without inventing
    /// a new gesture when it becomes enabled again. Retain its phase and clock.
    mutating func cancelCurrentGesture() {
        axis = .outside
        hasResolved = true
    }

    mutating func consume(_ input: Input, isInside: Bool) -> Decision {
        guard input.deltaX.isFinite, input.deltaY.isFinite, input.timestamp.isFinite else {
            reset()
            return .passThrough
        }
        guard input.phase != .mayBegin else { return .passThrough }

        // Momentum can arrive after a zero-delta .ended, or with no ordinary
        // phase at all. It never starts a new recognition, even after a long gap.
        if input.isMomentum {
            lastTimestamp = input.timestamp
            hasActivePhase = false
            hasFinished = true
            return axis == .horizontal ? .consumed : .passThrough
        }

        let followsIdleGap =
            lastTimestamp.map {
                !hasActivePhase && input.timestamp - $0 > Self.phaseLessIdleInterval
            } ?? true
        if input.phase == .began || followsIdleGap {
            reset()
            axis = isInside ? .undecided : .outside
        }
        lastTimestamp = input.timestamp

        // Terminal events must run before nonzero-delta and axis filters, and
        // still belong to a claimed gesture after the pointer leaves the region.
        if input.phase == .ended || input.phase == .cancelled {
            hasActivePhase = false
            hasFinished = true
            return axis == .horizontal ? .consumed : .passThrough
        }
        if hasFinished {
            return axis == .horizontal ? .consumed : .passThrough
        }
        if input.phase == .began || input.phase == .changed {
            hasActivePhase = true
        }
        guard axis != .outside, axis != .vertical else { return .passThrough }
        if hasResolved { return .consumed }

        let threshold = input.isPrecise ? Self.preciseThreshold : Self.wheelThreshold
        let recognitionDistance: CGFloat = input.isPrecise ? 8 : 0.25
        let limit = threshold * 100
        accumulatedX = min(limit, max(-limit, accumulatedX + input.deltaX))
        accumulatedY = min(limit, max(-limit, accumulatedY + input.deltaY))

        if axis == .undecided {
            if abs(accumulatedY) >= recognitionDistance,
                abs(accumulatedY) >= abs(accumulatedX) * Self.horizontalDominance
            {
                axis = .vertical
                return .passThrough
            }
            guard abs(accumulatedX) >= recognitionDistance,
                abs(accumulatedX) >= abs(accumulatedY) * Self.horizontalDominance
            else { return .passThrough }
            axis = .horizontal
            initialDirection = accumulatedX < 0 ? -1 : 1
        }

        // Returning across the origin before acceptance abandons this candidate.
        // It does not select the opposite Space later in the same gesture.
        guard accumulatedX * initialDirection > 0 else {
            hasResolved = true
            return .consumed
        }
        guard abs(accumulatedX) >= threshold else { return .consumed }
        hasResolved = true
        return .step(initialDirection < 0 ? .next : .previous)
    }
}
