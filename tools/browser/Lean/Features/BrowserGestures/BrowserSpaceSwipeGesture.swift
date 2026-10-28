import AppKit

/// Crest's phase routing and release projection, over Lean's existing sidebar hosts.
@MainActor final class BrowserSpaceSwipeGesture {
    private enum Axis { case outside, undecided, horizontal, vertical }
    private struct Sample {
        let time: TimeInterval
        let position: CGFloat
    }
    private weak var viewport: BrowserSidebarSpaceViewport?
    private var axis = Axis.outside
    private var token: Int?
    private var claimed = false
    private var position: CGFloat = 0
    private var samples: [Sample] = []
    private var wheel = BrowserSpaceScrollGesture()

    init(viewport: BrowserSidebarSpaceViewport) { self.viewport = viewport }

    func cancelCurrentGesture() {
        axis = .outside
        token = nil
        claimed = false
        samples.removeAll(keepingCapacity: true)
        position = 0
        wheel.cancelCurrentGesture()
    }

    func handle(_ event: NSEvent, isInside: Bool, enabled: Bool) -> NSEvent? {
        guard let viewport, event.window === viewport.window else { return event }
        guard event.scrollingDeltaX.isFinite, event.scrollingDeltaY.isFinite, event.timestamp.isFinite else {
            viewport.cancelInteractiveMotion()
            cancelCurrentGesture()
            return event
        }
        if event.phase.contains(.began) {
            axis = isInside && enabled ? .undecided : .outside
            token = nil
            claimed = false
            position = 0
            samples = [Sample(time: event.timestamp, position: 0)]
        }
        guard enabled else {
            viewport.cancelInteractiveMotion()
            cancelCurrentGesture()
            _ = wheel.consume(event, isInside: false, rightToLeft: viewport.rightToLeft)
            return event
        }
        if !event.momentumPhase.isEmpty { return claimed ? nil : event }
        if event.phase.contains(.ended) || event.phase.contains(.cancelled), let token {
            if event.scrollingDeltaX != 0 { _ = move(event, token: token) }
            viewport.endInteractiveMotion(
                velocity: velocity(at: event.timestamp), cancelled: event.phase.contains(.cancelled), token: token)
            self.token = nil
            axis = .outside
            return nil
        }
        if !event.hasPreciseScrollingDeltas || event.phase.isEmpty || viewport.reduceMotion {
            let decision = wheel.consume(event, isInside: isInside, rightToLeft: viewport.rightToLeft)
            if let step = decision.step { viewport.stepSpace(step) }
            claimed = decision.consumesEvent
            return claimed ? nil : event
        }
        if event.phase.contains(.mayBegin) { return event }
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            axis = .outside
            return claimed ? nil : event
        }
        guard event.phase.contains(.began) || event.phase.contains(.changed),
            axis != .outside, axis != .vertical
        else { return event }
        if axis == .undecided {
            guard event.scrollingDeltaX != 0 || event.scrollingDeltaY != 0 else { return event }
            guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else {
                axis = .vertical
                return event
            }
            guard isInside, let token = viewport.beginInteractiveMotion() else {
                axis = .outside
                return event
            }
            self.token = token
            claimed = true
            axis = .horizontal
        }
        guard let token, move(event, token: token) else {
            cancelCurrentGesture()
            return event
        }
        return nil
    }

    private func move(_ event: NSEvent, token: Int) -> Bool {
        position += event.scrollingDeltaX
        samples.append(Sample(time: event.timestamp, position: position))
        samples.removeAll { $0.time < event.timestamp - 0.08 }
        return viewport?.updateInteractiveMotion(deltaX: event.scrollingDeltaX, token: token) ?? false
    }

    private func velocity(at time: TimeInterval) -> CGFloat {
        guard let last = samples.last, time - last.time <= 0.08,
            let first = samples.first, last.time > first.time
        else { return 0 }
        return (last.position - first.position) / (last.time - first.time)
    }
}
