import Foundation

struct SessionMutation {
    enum Stage {
        case launch, tabUse, pageReport, transfer, batch, batchDeletion, deletion, expiry, creation, edit, withdrawal,
            removal, importing
    }
    var session: SessionState.Seed
    var stage: Stage?
    var followUp: SessionWindowFollowUp?
    var effects: [any CoreChange] = []
    var sweep: Sweep?
}

/// Evaluates one session edit on owned values. Committing and publishing are separate.
struct SessionMutations {
    struct Unsupported: Error { let operation: String }
    let workspaceID: UUID
    let kind: WorkspaceKind
    let basis: SessionState.Seed
    let windows: [UUID: SessionWindow]
    let now: Date
    let ids: () -> UUID
    var lastSweep: SessionMutation.Sweep? = nil

    func space(_ id: UUID) throws -> SpaceState.Seed {
        guard let value = basis.spaces.first(where: { $0.id == id }) else {
            throw Rejection.unknownSpace(UnknownSpace(spaceID: id))
        }
        guard !basis.spaceDeletions.contains(where: { $0.spaceID == id }) else {
            throw Rejection.spaceBeingDeleted(SpaceBeingDeleted(spaceID: id))
        }
        return value
    }
    func window(_ id: UUID) -> SessionWindowFollowUp {
        SessionWindowFollowUp(window: windows[id].flatMap { $0.workspaceID == workspaceID ? $0 : nil })
    }
    func requireOwnedSpaces() throws {
        guard kind.ownsSpaces else {
            throw Rejection.borrowedProfileRequiresOwner(BorrowedProfileRequiresOwner(workspaceID: workspaceID))
        }
    }
    func requirePreferences() throws {
        guard kind.keepsAppPreferences else {
            throw Rejection.persistentWorkspaceRequired(PersistentWorkspaceRequired(workspaceID: workspaceID))
        }
    }
    func replacing(
        _ spaces: [SpaceState.Seed], stage: SessionMutation.Stage?, followUp: SessionWindowFollowUp? = nil,
        effects: [any CoreChange] = []
    ) -> SessionMutation {
        var next = basis
        for space in spaces {
            if let index = next.spaces.firstIndex(where: { $0.id == space.id }) { next.spaces[index] = space }
        }
        return SessionMutation(session: next, stage: stage, followUp: followUp, effects: effects)
    }
    func organizing(_ id: UUID, stage: SessionMutation.Stage = .edit, _ change: (inout SessionTabs) throws -> Void)
        throws -> SessionMutation
    {
        let original = try space(id)
        var values = try SessionTabs(original)
        try change(&values)
        return replacing([values.capture(original)], stage: stage)
    }
    func absolute(_ spelling: String) throws -> URL {
        if let url = URL(string: spelling), let scheme = url.scheme?.lowercased() {
            if ["http", "https"].contains(scheme), BrowserAddress.webURL(spelling) == nil {
                throw Rejection.unsupportedAddress(UnsupportedAddress(url: spelling))
            }
            if scheme == "file", !spelling.lowercased().hasPrefix("file://") {
                throw Rejection.unsupportedAddress(UnsupportedAddress(url: spelling))
            }
            return url
        }
        if spelling.hasPrefix("/") { return URL(fileURLWithPath: spelling) }
        throw Rejection.unsupportedAddress(UnsupportedAddress(url: spelling))
    }
    func newTab(_ id: UUID, content: TabContent, placement: TabPlacement) throws -> TabState.Seed {
        guard content.address == nil || content.view == nil else {
            throw Rejection.invalidTabContent(InvalidTabContent(tabID: id))
        }
        var value = TabState.Seed.startPage(id: id, placement: placement, lastActivatedAt: now)
        if let view = content.view {
            value.title = view.title.key
            value.symbol = view.symbol
            value.nativeContent = NativeTabContent(kind: view.name, resourceID: nil)
        } else if let spelling = content.address {
            let address = try absolute(spelling)
            let host = URLComponents(url: address, resolvingAgainstBaseURL: false)?.host?.lowercased() ?? ""
            value.title = content.title.flatMap { $0.isEmpty ? nil : $0 } ?? (host.isEmpty ? spelling : host)
            value.url = spelling
            value.savedURL = placement.isDurable ? spelling : nil
            value.symbol = TabIconMode.webSymbol
        }
        return try SessionTabs.restored(value)
    }
    func startingCopies(_ copies: [SessionTabs.Copy], in values: inout SessionTabs, appearances: [TabPageAppearance]?)
        throws -> [any CoreChange]
    {
        for copy in copies {
            let value = try values.tab(copy.copy)
            if value.nativeContent == nil && value.url != nil,
                let appearance = appearances?.first(where: { $0.tabID == copy.source })
            {
                try values.edit(copy.copy) {
                    if let address = appearance.address {
                        $0.url = address
                        $0.nativeContent = nil
                    }
                    if !appearance.title.isEmpty { $0.title = appearance.title }
                }
            }
        }
        return copies.map { TabCopied(workspaceID: workspaceID, sourceTabID: $0.source, copyTabID: $0.copy) }
    }
    func apply(_ request: some SessionIntent) throws -> SessionMutation? {
        if let changed = try drop(request) { return changed }
        if let changed = try liveFolder(request) { return changed }
        if let request = request as? MoveTabToWindow { return try moveWithinWorkspace(request) }
        if let request = request as? ImportSpaces { return try importing(request) }
        if let request = request as? ImportReviewedSpaces { return try importing(request) }
        if request is SweepExpiredRecords { return try recordEdit(request) }
        if let changed = try tabEdit(request) { return changed }
        if let changed = try organizationEdit(request) { return changed }
        if let changed = try batchEdit(request) { return changed }
        if let request = request as? MoveTabToSpace { return try move(request) }
        if let changed = try recordEdit(request) { return changed }
        if let changed = try spaceEdit(request) { return changed }
        throw Unsupported(operation: String(describing: type(of: request)))
    }
}
