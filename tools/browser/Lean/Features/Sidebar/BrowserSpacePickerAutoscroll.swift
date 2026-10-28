// Adapted from Crest's Space-picker edge scrolling and display clock.
import AppKit
import QuartzCore
import SwiftUI

/// Uses the enclosing native scroll view, including manual scrolling during a
/// lift. Only its actual bounds delta is applied to the frozen reorder geometry.
struct BrowserSpacePickerAutoscroll: NSViewRepresentable {
    let viewport: CGRect
    let pointer: CGPoint?
    let contentMoved: (CGFloat) -> Void

    func makeNSView(context: Context) -> BrowserSpacePickerAutoscrollView {
        BrowserSpacePickerAutoscrollView()
    }

    func updateNSView(_ view: BrowserSpacePickerAutoscrollView, context: Context) {
        view.update(viewport: viewport, pointer: pointer, contentMoved: contentMoved)
    }

    static func dismantleNSView(_ view: BrowserSpacePickerAutoscrollView, coordinator: ()) {
        view.disconnect()
    }
}

@MainActor
final class BrowserSpacePickerAutoscrollView: NSView {
    private weak var clipView: NSClipView?
    private var observer: NSObjectProtocol?
    private var wasPostingBoundsChanges = false
    private lazy var autoscrollClock = BrowserSpaceAutoscrollClock { [weak self] scale in
        self?.advance(scale: scale)
    }
    private var viewport = CGRect.zero
    private var pointer: CGPoint?
    private var lastOriginX: CGFloat = 0
    private var contentMoved: ((CGFloat) -> Void)?
    private var connectionScheduled = false

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { disconnect() } else { connectSoon() }
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if superview == nil { disconnect() } else { connectSoon() }
    }

    func update(viewport: CGRect, pointer: CGPoint?, contentMoved: @escaping (CGFloat) -> Void) {
        self.viewport = viewport
        self.pointer = pointer
        self.contentMoved = contentMoved
        connectSoon()
        updateAutoscroll()
    }

    private func connectSoon() {
        guard clipView == nil, !connectionScheduled else { return }
        connectionScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            connectionScheduled = false
            guard window != nil, let scrollView = enclosingScrollView else { return }
            let clip = scrollView.contentView
            clipView = clip
            lastOriginX = clip.bounds.minX
            wasPostingBoundsChanges = clip.postsBoundsChangedNotifications
            clip.postsBoundsChangedNotifications = true
            observer = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification, object: clip, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.boundsChanged() }
            }
            updateAutoscroll()
        }
    }

    private func boundsChanged() {
        guard let clipView else { return }
        let origin = clipView.bounds.minX
        let offset = lastOriginX - origin
        lastOriginX = origin
        if pointer != nil, offset != 0 { contentMoved?(offset) }
    }

    private func updateAutoscroll() {
        guard window != nil, let pointer, clipView != nil,
            BrowserSpaceReorderLayout.autoscrollStep(at: pointer, in: viewport) != 0
        else {
            autoscrollClock.stop()
            return
        }
        autoscrollClock.start(in: self)
    }

    private func advance(scale: CGFloat) {
        guard window != nil, let pointer, let clipView, let scrollView = clipView.enclosingScrollView,
            let document = scrollView.documentView
        else {
            autoscrollClock.stop()
            return
        }
        let step = BrowserSpaceReorderLayout.autoscrollStep(at: pointer, in: viewport) * scale
        guard step != 0 else {
            autoscrollClock.stop()
            return
        }
        let origin = clipView.bounds.origin
        let maximum = max(document.bounds.minX, document.bounds.maxX - clipView.bounds.width)
        let newX = min(max(origin.x + step, document.bounds.minX), maximum)
        guard newX != origin.x else {
            autoscrollClock.stop()
            return
        }
        clipView.scroll(to: CGPoint(x: newX, y: origin.y))
        scrollView.reflectScrolledClipView(clipView)
    }

    func disconnect() {
        autoscrollClock.stop()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        clipView?.postsBoundsChangedNotifications = wasPostingBoundsChanges
        clipView = nil
        pointer = nil
        contentMoved = nil
    }
}

/// Advances the existing 60 Hz scroll distances at the view's display cadence.
@MainActor
private final class BrowserSpaceAutoscrollClock {
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
        weak var clock: BrowserSpaceAutoscrollClock?

        init(clock: BrowserSpaceAutoscrollClock) { self.clock = clock }

        @objc func tick(_ link: CADisplayLink) {
            clock?.tick(link)
        }
    }
}
