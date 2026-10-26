import AppKit

@MainActor
final class BrowserExtensionPopupAnchor {
    // MARK: - Static Variables

    private static let anchorWidth: CGFloat = 28
    private static let anchorHeight: CGFloat = 1
    private static let topLeadingFallbackOffset = CGPoint(x: 292, y: 36)

    // MARK: - Variables

    let screenPoint: CGPoint
    private weak var sourceWindow: NSWindow?
    private weak var sourceView: NSView?
    private let fallbackOffset: CGPoint

    // MARK: - Initializers

    init(screenPoint: CGPoint, sourceWindow: NSWindow?) {
        self.screenPoint = screenPoint
        self.sourceWindow = sourceWindow
        sourceView = nil
        fallbackOffset = .zero
    }

    init(sourceView: NSView) {
        self.sourceView = sourceView
        sourceWindow = sourceView.window
        fallbackOffset = .zero
        guard let window = sourceView.window else {
            screenPoint = CGPoint(
                x: sourceView.bounds.midX,
                y: sourceView.bounds.midY
            )
            return
        }
        let windowRect = sourceView.convert(sourceView.bounds, to: nil)
        let screenRect = window.convertToScreen(windowRect)
        screenPoint = CGPoint(x: screenRect.midX, y: screenRect.midY)
    }

    private init(
        screenPoint: CGPoint,
        sourceWindow: NSWindow?,
        sourceView: NSView?,
        fallbackOffset: CGPoint
    ) {
        self.screenPoint = screenPoint
        self.sourceWindow = sourceWindow
        self.sourceView = sourceView
        self.fallbackOffset = fallbackOffset
    }

    // MARK: - Actions - Presentation

    func offsetBy(
        dx: CGFloat = 0,
        dy: CGFloat = 0
    ) -> BrowserExtensionPopupAnchor {
        BrowserExtensionPopupAnchor(
            screenPoint: screenPoint,
            sourceWindow: sourceWindow,
            sourceView: sourceView,
            fallbackOffset: CGPoint(
                x: fallbackOffset.x + dx,
                y: fallbackOffset.y + dy
            )
        )
    }

    func replacingSourceWindow(
        _ window: NSWindow?
    ) -> BrowserExtensionPopupAnchor {
        // A popover can disappear before its action is presented. Capture the
        // live source location at the click, not its last SwiftUI layout pass.
        let point: CGPoint
        if let sourceView, let sourceWindow = sourceView.window {
            let rect = sourceWindow.convertToScreen(sourceView.convert(sourceView.bounds, to: nil))
            point = CGPoint(x: rect.midX, y: rect.midY)
        } else {
            point = screenPoint
        }
        return BrowserExtensionPopupAnchor(
            screenPoint: CGPoint(
                x: point.x + fallbackOffset.x,
                y: point.y + fallbackOffset.y
            ),
            sourceWindow: window,
            sourceView: nil,
            fallbackOffset: .zero
        )
    }

    func contentView(fallbackWindow: NSWindow?) -> NSView? {
        sourceWindow?.contentView ?? fallbackWindow?.contentView
    }

    func contains(event: NSEvent) -> Bool {
        guard let sourceView, let window = sourceView.window, event.window === window else { return false }
        return sourceView.bounds.contains(sourceView.convert(event.locationInWindow, from: nil))
    }

    func presentationSource(
        fallbackWindow: NSWindow?
    ) -> (view: NSView, rect: CGRect)? {
        if let sourceView, sourceView.window != nil {
            return (sourceView, sourceView.bounds)
        }
        guard let hostView = contentView(fallbackWindow: fallbackWindow) else {
            return nil
        }
        let adjustedScreenPoint = CGPoint(
            x: screenPoint.x + fallbackOffset.x,
            y: screenPoint.y + fallbackOffset.y
        )
        let windowPoint =
            hostView.window?.convertPoint(
                fromScreen: adjustedScreenPoint
            ) ?? adjustedScreenPoint
        let interactionPoint = hostView.convert(windowPoint, from: nil)
        return (
            hostView,
            Self.anchorRect(
                in: hostView.bounds,
                interactionPoint: interactionPoint
            )
        )
    }

    /// A thin rect centred on `interactionPoint` when it falls inside
    /// `bounds`, else near the top leading corner, kept inside `bounds`.
    private static func anchorRect(
        in bounds: CGRect,
        interactionPoint: CGPoint?
    ) -> CGRect {
        let point =
            interactionPoint.flatMap { bounds.contains($0) ? $0 : nil }
            ?? CGPoint(
                x: min(
                    bounds.maxX - anchorWidth / 2,
                    bounds.minX + topLeadingFallbackOffset.x
                ),
                y: bounds.maxY - topLeadingFallbackOffset.y
            )
        let centerX = min(
            max(point.x, bounds.minX + anchorWidth / 2),
            bounds.maxX - anchorWidth / 2
        )
        let centerY = min(max(point.y, bounds.minY), bounds.maxY)
        return CGRect(
            x: centerX - anchorWidth / 2,
            y: centerY - anchorHeight / 2,
            width: anchorWidth,
            height: anchorHeight
        )
    }
}
