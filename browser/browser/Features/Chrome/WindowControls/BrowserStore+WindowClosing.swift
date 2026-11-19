import AppKit

extension BrowserStore {
    func canCloseWindow(isLastWindow: @MainActor () -> Bool) async -> Bool {
        guard !isClosed else { return false }
        let spaceID = activeSpace.id
        let visible = Set(visiblePages.map(\.id))
        func removesPrivateSpace() -> Bool {
            activeSpace.isPrivate
                && !owner.contexts.values.contains {
                    !$0.isClosed && $0.id != id && $0.activeSpace.id == spaceID
                }
        }
        let removesSpace = removesPrivateSpace()
        // Closing the last private window ends its Space. Shared pages survive window closure.
        let ids = removesSpace ? activeSpace.tabs.map(\.id) : []
        let check = BrowserPageCloseCheck(ids, owner: owner)
        func isCurrent() -> Bool {
            !isClosed && activeSpace.id == spaceID && Set(visiblePages.map(\.id)) == visible
                && (!removesSpace || Set(activeSpace.tabs.map(\.id)) == Set(ids))
                && removesPrivateSpace() == removesSpace && check.isCurrent(in: owner)
        }
        guard await check.prepare(in: owner), isCurrent() else { return false }
        if removesSpace {
            guard await prepareToDeleteSpace(spaceID), isCurrent(),
                owner.activeDownloadRequests(in: spaceID).isEmpty
            else { return false }
        }
        if isLastWindow() && !owner.activeDownloadRequests().isEmpty {
            let requests = owner.activeDownloadRequests()
            let alert = NSAlert()
            alert.messageText = "Downloads are still running"
            alert.informativeText = "They will continue while Browser is open."
            alert.addButton(withTitle: "Keep Window Open")
            alert.addButton(withTitle: "Close Window")
            guard await BrowserDialogs.ask(alert, in: window) == .alertSecondButtonReturn,
                owner.downloadRequestsMatch(requests)
            else { return false }
        }
        guard isCurrent() else { return false }
        guard flush() else {
            showNotice("The session could not be saved.")
            return false
        }
        return true
    }

    func closeWindow() {
        guard !isClosed else { return }
        isClosed = true
        windowState.isOpen = false
        let remaining = owner.contexts.values.filter { !$0.isClosed }
        if owner.activeWindowID == id { owner.activeWindowID = remaining.first?.id }
        for page in pages.values where page.hostingWindowID == id || page.owner === self {
            let presenter = remaining.first { $0.visiblePages.contains(where: { $0.id == page.id }) }
            if page.hostingWindowID == id {
                page.webView.removeFromSuperview()
                page.hostingWindowID = presenter?.id
            }
            if page.owner === self { page.owner = presenter ?? remaining.first ?? self }
        }
        runtimeRevision &+= 1
        if activeSpace.isPrivate && !remaining.contains(where: { $0.activeSpace.id == activeSpace.id }) {
            deleteSpace(activeSpace.id, prepared: true)
        }
        changed()
    }
}
