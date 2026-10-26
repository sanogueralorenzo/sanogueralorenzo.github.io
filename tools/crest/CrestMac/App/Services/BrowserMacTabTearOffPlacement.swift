import AppKit

/// Positions a tear-off once, using the destination row's actual layout.
/// Placement is transient presentation state, separate from the tab transfer.
@MainActor
final class BrowserMacTabTearOffPlacement {
    let assignment: BrowserTabRuntimeAssignment
    let dropPoint: CGPoint
    let grabFraction: CGPoint
    private(set) var isPending = true
    private weak var window: NSWindow?
    private var originalIgnoresMouseEvents = false
    private var fallback: Task<Void, Never>?
    private var onReveal: (() -> Void)?

    init(assignment: BrowserTabRuntimeAssignment, dropPoint: CGPoint, grabFraction: CGPoint) {
        self.assignment = assignment
        self.dropPoint = dropPoint
        self.grabFraction = grabFraction
    }

    /// Runs before SwiftUI orders the native window in, avoiding a flash at its
    /// default location while the transferred tab waits for its first layout.
    func prepare(_ window: NSWindow) {
        guard isPending, self.window !== window else { return }
        self.window = window
        originalIgnoresMouseEvents = window.ignoresMouseEvents
        window.ignoresMouseEvents = true
        window.alphaValue = 0
        position(contentAnchor: CGPoint(x: contentScreenFrame(in: window).width / 2, y: 0))
    }

    func attach(_ window: NSWindow, onReveal: @escaping () -> Void) {
        prepare(window)
        guard isPending else { return }
        self.onReveal = onReveal
        fallback?.cancel()
        fallback = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            // The tab already belongs to this workspace. If layout cannot
            // report a row, reveal it at the drop rather than discard the tab.
            self?.reveal()
        }
    }

    func place(at row: BrowserSidebarReorderRow) {
        guard isPending, row.id == .tab(assignment.tabID),
            row.space.spaceID == assignment.spaceID, row.space.profileID == assignment.profileID,
            row.frame.width > 0, row.frame.height > 0, window != nil
        else { return }
        let anchor = CGPoint(
            x: row.frame.minX + row.frame.width * grabFraction.x,
            y: row.frame.minY + row.frame.height * grabFraction.y)
        position(contentAnchor: anchor)
        reveal()
    }

    func cancel() {
        isPending = false
        fallback?.cancel()
        fallback = nil
        onReveal = nil
        window?.ignoresMouseEvents = originalIgnoresMouseEvents
        window?.alphaValue = 1
        window = nil
    }

    private func position(contentAnchor: CGPoint) {
        guard let window else { return }
        let content = contentScreenFrame(in: window)
        var frame = window.frame.offsetBy(
            dx: dropPoint.x - (content.minX + contentAnchor.x),
            dy: dropPoint.y - (content.maxY - contentAnchor.y))
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(dropPoint) }) ?? window.screen
            ?? NSScreen.main
        {
            let visible = screen.visibleFrame
            frame.origin.x = max(visible.minX, min(frame.minX, visible.maxX - frame.width))
            frame.origin.y = min(visible.maxY - frame.height, max(frame.minY, visible.minY))
        }
        window.setFrame(frame, display: false, animate: false)
    }

    private func contentScreenFrame(in window: NSWindow) -> CGRect {
        window.convertToScreen(window.contentView?.frame ?? CGRect(origin: .zero, size: window.frame.size))
    }

    private func reveal() {
        guard isPending, let window else { return }
        isPending = false
        fallback?.cancel()
        fallback = nil
        window.ignoresMouseEvents = originalIgnoresMouseEvents
        window.alphaValue = 1
        window.makeKeyAndOrderFront(nil)
        onReveal?()
        onReveal = nil
    }
}
