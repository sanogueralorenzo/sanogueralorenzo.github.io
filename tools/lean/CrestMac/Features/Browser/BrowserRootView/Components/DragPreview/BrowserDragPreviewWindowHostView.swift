import AppKit
import SwiftUI

/// Owns the transparent child window everything travelling on the pointer is
/// drawn in — a lifted sidebar row, a carried Split View card — for as long as it
/// is travelling.
///
/// A child window rather than an overlay view, because the thing it has to beat
/// is not a SwiftUI sibling. The page is a `WKWebView`, an `NSView` subtree
/// inside the same hosting view, and AppKit composites view subtrees above
/// everything SwiftUI draws in that host regardless of `zIndex`. Ordering is
/// only decided in SwiftUI's favour one level up, between windows: a child
/// window ordered above its parent paints above the parent's entire content,
/// web views included. It is also what AppKit's own dragging session used before
/// this release replaced it, for exactly this reason.
///
/// It takes the preview at the lift rather than at the page boundary. Handing a
/// travelling preview between two hosts leaves it clipped everywhere it is drawn
/// by the losing one — not only over the page, but by window chrome, by the
/// insets around the content area, and by whatever a view transition is passing
/// through at that moment. One owner for the whole lift has no such seam.
///
/// The window is inert. It ignores mouse events, never becomes key, casts no
/// shadow, and grows beyond the parent to contain a preview carried outside
/// it. The drawing canvas keeps the parent's coordinates. Clicks, scrolls,
/// and hovers reach the page underneath as if it were not there.
///
/// This view is the drag's presentation and nothing else: it holds no drag state
/// and makes no decisions about when a lift floats. The reorder state answers
/// that, SwiftUI hands the answer down, and this view puts a window around it.
@MainActor
final class BrowserDragPreviewWindowHostView: NSView {
    var onSidebarLandingComplete: (UUID) -> Void = { _ in }
    var onSidebarLandingArrived: (UUID) -> Void = { _ in }
    /// What to draw, or `nil` to take the window down.
    var content: BrowserDragPreviewWindowContent? {
        didSet {
            guard content != oldValue else { return }
            apply()
        }
    }

    private var presentation: BrowserDragPreviewWindowPresentation?
    private var panel: NSPanel?
    private var hostingView: NSHostingView<BrowserDragPreviewWindowFloatingContent>?
    private var windowObservers: [NSObjectProtocol] = []

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observeParentWindow()
        apply()
    }

    /// Takes the preview window down and stops observing. Safe to call twice.
    func teardown() {
        stopObservingParentWindow()
        guard let panel else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        panel.contentView = nil
        hostingView = nil
        presentation = nil
        self.panel = nil
    }

    private func apply() {
        guard let content, let parent = window, parent.isKeyWindow else {
            teardownPreviewOnly()
            return
        }
        let sourceFrame = parent.convertToScreen(contentRect(of: parent))
        let drawingBounds = content.drawingBounds
        let previewFrame = CGRect(
            x: sourceFrame.minX + drawingBounds.minX,
            y: sourceFrame.maxY - drawingBounds.maxY,
            width: drawingBounds.width, height: drawingBounds.height)
        let frame = sourceFrame.union(previewFrame)
        let canvasFrame = CGRect(
            x: sourceFrame.minX - frame.minX, y: frame.maxY - sourceFrame.maxY,
            width: sourceFrame.width, height: sourceFrame.height)
        let panel = panel ?? makePanel(for: parent)
        if let presentation {
            presentation.content = content
            presentation.canvasFrame = canvasFrame
        } else {
            let presentation = BrowserDragPreviewWindowPresentation(content: content, canvasFrame: canvasFrame)
            presentation.onSidebarLandingComplete = { [weak self] id in self?.onSidebarLandingComplete(id) }
            presentation.onSidebarLandingArrived = { [weak self] id in self?.onSidebarLandingArrived(id) }
            self.presentation = presentation
            let hostingView = NSHostingView(
                rootView: BrowserDragPreviewWindowFloatingContent(presentation: presentation))
            hostingView.autoresizingMask = [.width, .height]
            panel.contentView = hostingView
            self.hostingView = hostingView
        }
        panel.appearance = parent.effectiveAppearance
        if panel.frame != frame {
            panel.setFrame(frame, display: false)
        }
        if panel.parent !== parent {
            hostingView?.layoutSubtreeIfNeeded()
            parent.addChildWindow(panel, ordered: .above)
        }
    }

    /// The parent's content area, in the parent's own coordinates.
    ///
    /// The browser window uses a full-size content view, so this is also the
    /// space the drag reports its pointer in: a preview placed at the drag's
    /// global origin inside the panel lands where the row would have been drawn.
    private func contentRect(of parent: NSWindow) -> CGRect {
        parent.contentView?.frame ?? CGRect(origin: .zero, size: parent.frame.size)
    }

    private func makePanel(for parent: NSWindow) -> NSPanel {
        let panel = NSPanel(
            contentRect: contentRect(of: parent),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
        panel.animationBehavior = .none
        self.panel = panel
        return panel
    }

    private func teardownPreviewOnly() {
        guard let panel else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        panel.contentView = nil
        hostingView = nil
        presentation = nil
        self.panel = nil
    }

    /// A window that closes, moves, or resizes mid-drag must not leave a preview
    /// floating over the desktop.
    private func observeParentWindow() {
        stopObservingParentWindow()
        guard let parent = window else { return }
        let center = NotificationCenter.default
        windowObservers = [
            center.addObserver(
                forName: NSWindow.willCloseNotification,
                object: parent,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.teardownPreviewOnly() }
            },
            center.addObserver(
                forName: NSWindow.didResizeNotification,
                object: parent,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.apply() }
            },
            center.addObserver(
                forName: NSWindow.didMoveNotification,
                object: parent,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.apply() }
            },
            center.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: parent,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.teardownPreviewOnly() }
            },
        ]
    }

    private func stopObservingParentWindow() {
        for observer in windowObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        windowObservers.removeAll()
    }
}
