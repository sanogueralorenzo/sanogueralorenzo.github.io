import AppKit

extension BrowserStore {
    func handleSidebarPointer(_ event: NSEvent) {
        guard let window = event.window else { return }
        if event.type == .leftMouseUp {
            for context in owner.contexts.values { context.isDragging = false }
        }
        if event.type == .swipe {
            if event.deltaY != 0 {
                adjacentSpace(event.deltaY > 0 ? -1 : 1)
            } else if event.deltaX > 0 {
                activePage?.webView.goBack()
            } else if event.deltaX < 0 {
                activePage?.webView.goForward()
            }
            return
        }
        let point = event.locationInWindow
        let onSidebar = showsSidebar && point.x < sidebarWidth + SidebarGeometry.inset
        if event.type == .leftMouseDown, !onSidebar, !addressPresented {
            sidebarKeyboardSelection = false
            selectedTabs.removeAll()
            selectedFolders.removeAll()
            selectionAnchor = nil
            selectionRangeBase = nil
            for page in visiblePages {
                let location = page.webView.convert(point, from: nil)
                if page.webView.window === window, page.webView.bounds.contains(location) {
                    if selectedTab?.id != page.id { selectTab(page.id) }
                    break
                }
            }
        }
    }
}
