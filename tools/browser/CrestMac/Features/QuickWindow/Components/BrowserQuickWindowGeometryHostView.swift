import AppKit

@MainActor
final class BrowserQuickWindowGeometryHostView: NSView {
    private weak var pagePoolRegistry: BrowserPagePoolRegistry?
    private var targetWindowID: UUID?
    private weak var positionedWindow: NSWindow?

    init(
        pagePoolRegistry: BrowserPagePoolRegistry?,
        targetWindowID: UUID?
    ) {
        self.pagePoolRegistry = pagePoolRegistry
        self.targetWindowID = targetWindowID
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        scheduleGeometryUpdate()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func configure(
        pagePoolRegistry: BrowserPagePoolRegistry?,
        targetWindowID: UUID?
    ) {
        guard
            self.pagePoolRegistry !== pagePoolRegistry
                || self.targetWindowID != targetWindowID
        else { return }
        self.pagePoolRegistry = pagePoolRegistry
        self.targetWindowID = targetWindowID
    }

    /// Sized against the page the Quick Window came from, else that page's
    /// window — a Start Page has no page view to measure — and only then the
    /// screen, capped so a wide display does not produce a giant window.
    static func targetFrame(
        sourceWebContentFrame: CGRect?,
        sourceWindowFrame: CGRect? = nil,
        fallbackVisibleFrame: CGRect
    ) -> CGRect {
        let usable: (CGRect?) -> CGRect? = { frame in
            guard let frame, frame.width > 0, frame.height > 0 else { return nil }
            return frame
        }
        if let referenceFrame = usable(sourceWebContentFrame) ?? usable(sourceWindowFrame) {
            return BrowserTransientCardArrangement.centeredWindowContentFrame(in: referenceFrame)
        }
        let proposed = BrowserTransientCardArrangement.centeredWindowContentFrame(in: fallbackVisibleFrame)
        let size = CGSize(
            width: min(proposed.width, BrowserQuickWindowLayout.maximumScreenFallbackWidth),
            height: min(proposed.height, BrowserQuickWindowLayout.maximumScreenFallbackHeight))
        return CGRect(
            x: fallbackVisibleFrame.midX - size.width / 2,
            y: fallbackVisibleFrame.midY - size.height / 2,
            width: size.width, height: size.height)
    }

    func updateWindowGeometry() {
        guard let window,
            positionedWindow !== window,
            let screen = window.screen ?? NSScreen.main
        else { return }
        positionedWindow = window
        let sourceWebContentFrame = targetWindowID.flatMap { targetWindowID in
            pagePoolRegistry?
                .runtime(for: targetWindowID)?
                .activeWebContentFrame
        }
        let sourceWindowFrame = targetWindowID.flatMap { targetWindowID in
            NSApp.windows.first {
                $0 !== window && $0.identifier?.rawValue == targetWindowID.uuidString
            }?.frame
        }
        let frame = Self.targetFrame(
            sourceWebContentFrame: sourceWebContentFrame,
            sourceWindowFrame: sourceWindowFrame,
            fallbackVisibleFrame: screen.visibleFrame
        )
        guard !framesApproximatelyEqual(window.frame, frame) else { return }
        window.setFrame(frame, display: true, animate: false)
    }

    private func scheduleGeometryUpdate() {
        DispatchQueue.main.async { [weak self] in
            self?.updateWindowGeometry()
        }
    }

    private func framesApproximatelyEqual(
        _ first: CGRect,
        _ second: CGRect
    ) -> Bool {
        abs(first.minX - second.minX) < 0.5
            && abs(first.minY - second.minY) < 0.5
            && abs(first.width - second.width) < 0.5
            && abs(first.height - second.height) < 0.5
    }
}
