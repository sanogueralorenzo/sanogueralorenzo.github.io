import AppKit

/// WebKit gets first chance to handle history swipes.
@MainActor final class BrowserWindow: NSWindow {
    weak var store: BrowserStore?

    override func swipe(with event: NSEvent) {
        if store?.handleUnhandledSwipe(event) == true { return }
        super.swipe(with: event)
    }
}

extension BrowserStore {
    private var allowsPointerNavigation: Bool {
        !isClosed && !addressPresented && window?.attachedSheet == nil
            && !isResizingSidebar && owner.sidebarDrag.payload == nil
    }

    func sidebarContains(_ event: NSEvent, excludingTitlebar: Bool = false) -> Bool {
        guard showsSidebar, let content = window?.contentView else { return false }
        let inset = SidebarGeometry.inset
        let top = excludingTitlebar ? SidebarGeometry.titlebarHeight : 0
        let rect = CGRect(
            x: content.bounds.minX + inset, y: content.bounds.minY + inset + (content.isFlipped ? top : 0),
            width: sidebarWidth, height: max(0, content.bounds.height - inset * 2 - top))
        return rect.contains(content.convert(event.locationInWindow, from: nil))
    }

    func handleSpaceScroll(_ event: NSEvent) -> NSEvent? {
        guard event.window === window, let sidebarSpaceViewport else { return event }
        let enabled = allowsPointerNavigation && utility == nil && session.spaces.count > 1
        let isInside = sidebarContains(event, excludingTitlebar: true) && !spaceSwitcherContains(event)
        return sidebarSpaceViewport.handleScroll(
            event, isInside: isInside, enabled: enabled)
    }

    func handleUnhandledSwipe(_ event: NSEvent) -> Bool {
        guard allowsPointerNavigation, event.window === window,
            event.deltaX.isFinite, event.deltaY.isFinite,
            abs(event.deltaX) > abs(event.deltaY)
        else { return false }
        let backward = event.deltaX > 0
        if sidebarContains(event) {
            guard !spaceSwitcherContains(event) else { return false }
            adjacentSpace(backward ? -1 : 1)
            return true
        }
        guard let content = window?.contentView else { return false }
        var hit = content.hitTest(content.convert(event.locationInWindow, from: nil))
        while let view = hit {
            if let page = visiblePages.first(where: { $0.webView === view }) {
                if backward { page.webView.goBack() } else { page.webView.goForward() }
                return true
            }
            hit = view.superview
        }
        guard let page = activePage,
            backward ? page.webView.canGoBack : page.webView.canGoForward
        else { return false }
        if backward { page.webView.goBack() } else { page.webView.goForward() }
        return true
    }

    private func spaceSwitcherContains(_ event: NSEvent) -> Bool {
        guard let content = window?.contentView else { return false }
        return sidebarReorder.spaceViewport.contains(content.convert(event.locationInWindow, from: nil))
    }
}
