import AppKit
import SwiftUI

/// Precise scrolling moves the sidebar in points. Ordinary wheels retain the
/// shared one-intent-per-burst policy; momentum cannot start a second page.
@MainActor
final class SpacePagerGesture<Content: View> {
    private enum Axis { case undecided, horizontal, vertical, outside }
    private struct Sample {
        let timestamp: TimeInterval
        let position: CGFloat
    }

    private weak var viewport: SpacePagerViewport<Content>?
    private var monitor: Any?
    private var axis = Axis.outside
    private var nativeToken: UInt?
    private var claimedGesture = false
    private var samples: [Sample] = []
    private var position: CGFloat = 0
    private let wheel = SpaceScrollGestureEventAdapter()

    init(viewport: SpacePagerViewport<Content>) { self.viewport = viewport }

    func attach(to window: NSWindow?) {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        cancelCurrentGesture()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }
            return handle(event)
        }
    }

    func cancelCurrentGesture() {
        axis = .outside
        nativeToken = nil
        claimedGesture = false
        samples.removeAll(keepingCapacity: true)
        position = 0
        wheel.cancelCurrentGesture()
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard let viewport, let window = viewport.window, event.window === window else { return event }
        let inside =
            !viewport.isHiddenOrHasHiddenAncestor && viewport.bounds.width > 0
            && viewport.gestureBounds.contains(viewport.convert(event.locationInWindow, from: nil))
        if event.phase.contains(.began) {
            axis = inside && !viewport.isInteractionLocked ? .undecided : .outside
            nativeToken = nil
            claimedGesture = false
            position = 0
            samples = [Sample(timestamp: event.timestamp, position: 0)]
        }
        guard !viewport.isInteractionLocked else {
            cancelCurrentGesture()
            return wheel.handle(
                event, isInside: inside, layoutDirection: viewport.layoutDirection,
                isEnabled: false, onStep: { _ in })
        }
        if !event.momentumPhase.isEmpty { return claimedGesture ? nil : event }
        if event.phase.contains(.ended) || event.phase.contains(.cancelled), let token = nativeToken {
            if event.scrollingDeltaX != 0 {
                _ = move(event, token: token)
            }
            _ = viewport.endInteractiveMotion(
                velocity: velocity(at: event.timestamp), cancelled: event.phase.contains(.cancelled), token: token)
            nativeToken = nil
            axis = .outside
            return nil
        }
        if !event.hasPreciseScrollingDeltas || event.phase.isEmpty || viewport.reduceMotion {
            return wheel.handle(
                event, isInside: inside, layoutDirection: viewport.layoutDirection,
                onStep: viewport.step)
        }
        if event.phase.contains(.mayBegin) { return event }
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            nativeToken = nil
            axis = .outside
            return claimedGesture ? nil : event
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
            guard inside, let token = viewport.beginInteractiveMotion() else {
                axis = .outside
                return event
            }
            nativeToken = token
            claimedGesture = true
            axis = .horizontal
        }
        guard let nativeToken else { return event }
        guard move(event, token: nativeToken) else {
            cancelCurrentGesture()
            return event
        }
        return nil
    }

    private func move(_ event: NSEvent, token: UInt) -> Bool {
        position += event.scrollingDeltaX
        samples.append(Sample(timestamp: event.timestamp, position: position))
        samples.removeAll { $0.timestamp < event.timestamp - 0.08 }
        return viewport?.updateInteractiveMotion(deltaX: event.scrollingDeltaX, token: token) ?? false
    }

    private func velocity(at timestamp: TimeInterval) -> CGFloat {
        guard let last = samples.last, timestamp - last.timestamp <= 0.08,
            let first = samples.first, last.timestamp > first.timestamp
        else { return 0 }
        return (last.position - first.position) / (last.timestamp - first.timestamp)
    }
}
