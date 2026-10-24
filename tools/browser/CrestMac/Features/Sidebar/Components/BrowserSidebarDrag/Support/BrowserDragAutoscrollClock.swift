import AppKit
import QuartzCore

/// Advances the existing 60 Hz scroll distances at the view's display cadence.
@MainActor
final class BrowserDragAutoscrollClock {
    private var link: CADisplayLink?
    private var lastTargetTimestamp: TimeInterval?
    private let advance: @MainActor (CGFloat) -> Void
    private lazy var target = FrameTarget(clock: self)

    init(advance: @escaping @MainActor (CGFloat) -> Void) {
        self.advance = advance
    }

    isolated deinit {
        link?.invalidate()
    }

    func start(in view: NSView) {
        guard link == nil, view.window != nil else { return }
        lastTargetTimestamp = nil
        let link = view.displayLink(target: target, selector: #selector(FrameTarget.tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
        lastTargetTimestamp = nil
    }

    private func tick(_ link: CADisplayLink) {
        let elapsed = link.targetTimestamp - (lastTargetTimestamp ?? link.timestamp)
        lastTargetTimestamp = link.targetTimestamp
        guard elapsed > 0 else { return }
        // A delayed callback must not jump several rows while the drag is held.
        advance(CGFloat(min(elapsed, 1 / 30) * 60))
    }

    /// The run loop retains the display link and its target, never the owner.
    @MainActor
    private final class FrameTarget: NSObject {
        weak var clock: BrowserDragAutoscrollClock?

        init(clock: BrowserDragAutoscrollClock) { self.clock = clock }

        @objc func tick(_ link: CADisplayLink) {
            clock?.tick(link)
        }
    }
}
