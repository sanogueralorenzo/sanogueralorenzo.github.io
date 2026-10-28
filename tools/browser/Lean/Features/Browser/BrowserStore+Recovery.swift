import AppKit
import WebKit

extension BrowserStore {
    func setSelectedTab(_ tabID: UUID?, in spaceID: UUID) {
        windowState.tabsBySpace[spaceID] = tabID
        if tabID == nil { windowState.emptySpaces.insert(spaceID) } else { windowState.emptySpaces.remove(spaceID) }
        if let index = session.spaces.firstIndex(where: { $0.id == spaceID }) {
            session.spaces[index].selectedTabID = tabID
        }
        if let tabID {
            windowState.recentTabs.removeAll { $0 == tabID }
            windowState.recentTabs.insert(tabID, at: 0)
            if let (s, t) = tabIndex(tabID) { session.spaces[s].tabs[t].lastUsed = Date() }
        }
    }

    func unloadSafely(_ id: UUID, automatic: Bool = false) async -> Bool {
        guard let page = pages[id] else { return true }
        if automatic && (owner.visiblePageIDs.contains(id) || page.isProtectedFromUnloading) { return false }
        let revision = page.documentRevision
        guard await page.prepareToClose(automatically: automatic) else { return false }
        await page.captureDocumentState()
        guard pages[id] === page, page.documentRevision == revision,
            !automatic || (!owner.visiblePageIDs.contains(id) && !page.isProtectedFromUnloading)
        else { return false }
        page.checkpointNativeState()
        unload(id)
        changed()
        return true
    }

    func prepareTabs(_ ids: [UUID]) async -> Bool {
        guard !isClosed else { return false }
        let check = BrowserPageCloseCheck(ids, owner: owner)
        return await check.prepare(in: owner) && !isClosed
    }

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
        let ids = removesSpace ? activeSpace.tabs.map(\.id) : visiblePages.map(\.id)
        let check = BrowserPageCloseCheck(ids, owner: owner)
        func isCurrent() -> Bool {
            !isClosed && activeSpace.id == spaceID && Set(visiblePages.map(\.id)) == visible
                && (!removesSpace || Set(activeSpace.tabs.map(\.id)) == Set(ids))
                && removesPrivateSpace() == removesSpace && check.isCurrent(in: owner)
        }
        guard await check.prepare(in: owner), isCurrent() else { return false }
        if removesSpace {
            guard await prepareToDeleteSpace(spaceID), isCurrent(),
                !activeDownloads.contains(where: { $0.spaceID == spaceID })
            else { return false }
        }
        if isLastWindow() && !activeDownloads.isEmpty {
            let jobs = Set(activeDownloads.map(\.id))
            let alert = NSAlert()
            alert.messageText = "Downloads are still running"
            alert.informativeText = "They will continue while Lean is open."
            alert.addButton(withTitle: "Keep Window Open")
            alert.addButton(withTitle: "Close Window")
            guard await BrowserDialogs.ask(alert, in: window) == .alertSecondButtonReturn,
                Set(activeDownloads.map(\.id)).isSubset(of: jobs)
            else { return false }
        }
        guard isCurrent() else { return false }
        guard flush() else {
            showNotice("The session could not be saved.")
            return false
        }
        return true
    }

}

/// An approval belongs to these page instances and documents, including tabs
/// that were asleep when the check began.
@MainActor
struct BrowserPageCloseCheck {
    private let ids: [UUID]
    private let documents: [UUID: BrowserPage]
    private let revisions: [UUID: Int]

    init(_ ids: [UUID], owner: BrowserSessionOwner) {
        var seen = Set<UUID>()
        self.ids = ids.filter { seen.insert($0).inserted }
        documents = Dictionary(uniqueKeysWithValues: self.ids.compactMap { id in owner.pages[id].map { (id, $0) } })
        revisions = documents.mapValues(\.documentRevision)
    }

    func isCurrent(in owner: BrowserSessionOwner) -> Bool {
        ids.allSatisfy { id in
            if let page = documents[id] {
                return owner.pages[id] === page && page.documentRevision == revisions[id]
            }
            return owner.pages[id] == nil
        }
    }

    func prepare(in owner: BrowserSessionOwner) async -> Bool {
        guard isCurrent(in: owner) else { return false }
        for id in ids {
            if let page = documents[id] {
                guard owner.pages[id] === page, await page.prepareToClose() else { return false }
            }
        }
        for page in documents.values {
            await page.captureDocumentState()
            page.checkpointNativeState()
        }
        return isCurrent(in: owner)
    }
}
