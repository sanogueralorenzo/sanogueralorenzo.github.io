import Foundation

extension BrowserStore {
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
