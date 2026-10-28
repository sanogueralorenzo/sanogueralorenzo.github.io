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
        let documents = Dictionary(uniqueKeysWithValues: Set(ids).compactMap { id in pages[id].map { (id, $0) } })
        let revisions = documents.mapValues(\.documentRevision)
        for id in ids {
            if let page = documents[id] {
                guard pages[id] === page, await page.prepareToClose() else { return false }
            }
        }
        for page in documents.values {
            await page.captureDocumentState()
            page.checkpointNativeState()
        }
        return !isClosed
            && ids.allSatisfy { id in
                if let page = documents[id] {
                    return pages[id] === page && page.documentRevision == revisions[id]
                }
                return pages[id] == nil
            }
    }

}
