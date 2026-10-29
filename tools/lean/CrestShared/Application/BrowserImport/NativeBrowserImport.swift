import Foundation

/// The process-local queue and review. CoreState exposes these same values;
/// only committing explicit choices edits the persisted browser session.
@MainActor
final class NativeBrowserImport {
    enum Failure: LocalizedError {
        case notOpen, busy
        var errorDescription: String? {
            switch self {
            case .notOpen: String(localized: "Import is no longer open. Open it again.")
            case .busy: String(localized: "Wait for the import to finish.")
            }
        }
    }
    private unowned let core: CrestCore
    init(core: CrestCore) { self.core = core }
    func send(_ intent: some BrowserImportIntent) throws {
        core.drain()
        try intent.apply(to: self)
    }
    func start(_ workspaceID: UUID) throws {
        guard let workspace = core.state.workspaces[workspaceID] else {
            throw Rejection.unknownWorkspace(UnknownWorkspace(workspaceID: workspaceID))
        }
        guard workspace.kind.keepsAppPreferences else {
            throw Rejection.persistentWorkspaceRequired(PersistentWorkspaceRequired(workspaceID: workspaceID))
        }
        if core.state.importFlow?.phase.isBusy == true { throw Failure.busy }
        core.state.importFlow = ImportFlowState(
            workspaceID: workspaceID, step: .importBrowser, phase: .idle, offered: [], selected: [], queue: nil,
            source: nil, review: nil, failure: nil, summary: nil)
    }
    func revise(_ action: (inout ImportFlowState, ImportReviewContext) throws -> Void) throws {
        guard var flow = core.state.importFlow, let workspace = core.state.workspaces[flow.workspaceID] else {
            throw Failure.notOpen
        }
        try action(&flow, ImportReviewContext(workspace))
        core.state.importFlow = flow
    }
    static func requireIdle(_ flow: ImportFlowState) throws {
        if flow.phase.isBusy { throw Failure.busy }
    }
    func edit(_ id: UUID, _ action: (inout ImportReviewSpace, ImportReviewContext) -> Void) throws {
        try revise { flow, context in
            try Self.requireIdle(flow)
            guard var review = flow.review else { return }
            review.edit(id, over: context) { action(&$0, context) }
            flow.review = review
        }
    }
    static func validate(_ spaces: [SpaceState]) throws {
        guard Set(spaces.map(\.id)).count == spaces.count else {
            throw Rejection.invalidImport(InvalidImport(flaw: .unpairedChoices))
        }
        guard spaces.count <= CapacityLimits.current.spaces else {
            throw Rejection.spaceLimitReached(SpaceLimitReached(limit: CapacityLimits.current.spaces))
        }
        for space in spaces {
            var retired: Set<UUID> = []
            var run: UUID?
            var placement: TabPlacement?
            var folder: UUID?
            var length = 0
            for tab in space.tabs {
                guard let group = tab.splitGroupID else {
                    if let run { retired.insert(run) }
                    run = nil
                    length = 0
                    continue
                }
                guard tab.placement.holdsSplits else {
                    throw Rejection.invalidImport(InvalidImport(flaw: .malformedSplit))
                }
                if run != group {
                    if let run { retired.insert(run) }
                    guard !retired.contains(group) else {
                        throw Rejection.invalidImport(InvalidImport(flaw: .malformedSplit))
                    }
                    run = group
                    placement = tab.placement
                    folder = tab.folderID
                    length = 1
                } else {
                    guard tab.placement == placement, tab.folderID == folder,
                        length < CapacityLimits.current.splitMembers
                    else { throw Rejection.invalidImport(InvalidImport(flaw: .malformedSplit)) }
                    length += 1
                }
            }
        }
    }
}

extension CrestCore {
    func send(_ intent: some BrowserImportIntent) throws { try browserImport.send(intent) }
}
