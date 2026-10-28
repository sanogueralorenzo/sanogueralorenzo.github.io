import Foundation

extension BrowserStore {
    /// Moves a tab within its Space, and answers whether it moved. The core
    /// takes a split member out of its split for a section that holds none.
    func moveSessionTab(
        _ id: UUID, in spaceID: UUID, to placement: TabPlacement,
        folderID: UUID? = nil, before anchor: UUID? = nil
    ) -> Bool {
        family.send(
            MoveTab(
                workspaceID: family.workspaceID, spaceID: spaceID, tabID: id, placement: placement,
                folderID: folderID, beforeTabID: anchor, leavesSplit: false),
            from: self)
    }

    /// The core has accepted each copy's identity and visible URL/title. The
    /// page owner now prepares its engine state before pages mount, from each
    /// source as it was before the intent.
    func prepareAcceptedCopies(_ copies: [TabCopied], from sources: BrowserTabCopySources) {
        for pair in copies {
            guard let source = sources.tabs[pair.sourceTabID] else { continue }
            tabCopying?.prepareTabCopy(from: source, copyID: pair.copyTabID, in: sources.space)
        }
    }

    /// Runs an intent the window issued in a Space that copies tabs, and
    /// prepares the pages of the copies it made from their sources as they
    /// were. Answers the copies, or nil when the core refused it.
    @discardableResult
    func sendCopying(_ intent: some Intent, in spaceID: UUID) -> [TabCopied]? {
        guard let space = spaceModel(spaceID) else { return nil }
        let sources = BrowserTabCopySources(space)
        guard let sent = family.perform(intent, from: self) else { return nil }
        let copies: [TabCopied] = sent.changes.compactMap {
            guard case .tabCopied(let copied) = $0, copied.workspaceID == family.workspaceID else { return nil }
            return copied
        }
        prepareAcceptedCopies(copies, from: sources)
        return copies
    }
}
