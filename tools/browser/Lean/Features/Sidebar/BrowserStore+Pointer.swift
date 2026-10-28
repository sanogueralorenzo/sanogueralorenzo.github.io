import AppKit

extension BrowserStore {
    func handleSidebarPointer(_ event: NSEvent) {
        guard !isClosed, let window = event.window, window === self.window else { return }
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
