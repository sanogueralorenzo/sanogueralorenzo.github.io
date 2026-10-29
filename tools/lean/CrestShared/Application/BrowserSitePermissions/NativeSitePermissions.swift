import Foundation

@MainActor
final class NativeSitePermissions {
    private unowned let core: CrestCore
    private let storage: PermissionSQLite?
    private var kept = PermissionLedger()
    private var passing = PermissionLedger()
    init(core: CrestCore) throws {
        self.core = core
        storage = try core.storageDirectory.map(PermissionSQLite.init(directory:))
        if let storage { kept.restore(try storage.read()) }
        for space in Set(kept.records.map(\.spaceID)) { publish(space, []) }
    }
    func send(_ action: some SitePermissionIntent) throws(PermissionFailure) {
        core.drain()
        try action.apply(to: self)
    }
    /// A seeded persistent-kind workspace still keeps nothing. The explicit
    /// workspace fact identifies the file's owner, before any borrowed view.
    private func keeps(_ space: UUID) -> Bool {
        storage != nil && core.state.workspaces.values.contains { $0.keepsFile && $0.spaces.contains(space) }
    }
    private func ledger(_ space: UUID) -> PermissionLedger { keeps(space) ? kept : passing }
    func decision(_ space: UUID, _ origin: SiteOrigin, _ permission: SitePermission, _ detail: String?)
        -> SitePermissionDecision
    {
        ledger(space).decision(space, origin, permission, detail)
    }
    func mediaDecision(_ space: UUID, _ origin: SiteOrigin, _ media: SitePermission) -> SitePermissionDecision {
        ledger(space).mediaDecision(space, origin, media)
    }
    private func save(_ next: PermissionLedger, adopting: Bool = false) throws(PermissionFailure) {
        do { try storage?.save(next.records, adopting: adopting) } catch let failure as PermissionSQLite.Failure {
            core.storageFailureHandler?(failure.reason)
            throw .storage(failure.reason)
        } catch { throw .storage(.unavailable) }
    }
    func decide(_ action: DecideSitePermission) throws(PermissionFailure) {
        let persistent = keeps(action.spaceID)
        var next = persistent ? kept : passing
        let changed = try next.set(action.spaceID, action.origin, action.permission, action.detail, action.decision)
        if persistent {
            if changed { try save(next) }
            kept = next
        } else {
            passing = next
        }
        publish(
            action.spaceID,
            [
                SitePermissionScope(
                    origin: action.origin, permission: action.permission, detail: action.detail,
                    revokesAuthorization: !action.decision.grants)
            ])
    }
    func reset(_ action: ResetSitePermission) throws(PermissionFailure) {
        var next = kept
        var record = next.reset(action.recordID)
        if record != nil {
            try save(next)
            kept = next
        } else {
            record = passing.reset(action.recordID)
        }
        if let record {
            publish(
                record.spaceID,
                [
                    SitePermissionScope(
                        origin: record.origin, permission: record.permission, detail: record.detail,
                        revokesAuthorization: true)
                ])
        }
    }
    func reset(_ action: ResetSpacePermissions) throws(PermissionFailure) {
        var next = kept
        if next.resetSpace(action.spaceID) { try save(next) }
        kept = next
        _ = passing.resetSpace(action.spaceID)
        publish(
            action.spaceID, [SitePermissionScope(origin: nil, permission: nil, detail: nil, revokesAuthorization: true)]
        )
    }
    func adopt(_ data: Data?) throws(PermissionFailure) {
        if let storage {
            do {
                if try !storage.hasAdopted() {
                    var next = kept
                    next.restore(kept.records + PermissionDocument.read(data))
                    try save(next, adopting: true)
                    kept = next
                }
            } catch let error as PermissionFailure { throw error } catch let error as PermissionSQLite.Failure {
                throw .storage(error.reason)
            } catch { throw .storage(.unavailable) }
        }
        for space in Set((kept.records + passing.records).map(\.spaceID)) { publish(space, []) }
    }
    private func publish(_ space: UUID, _ scopes: [SitePermissionScope]) {
        let records = (kept.records + passing.records).filter { $0.spaceID == space }.sorted(
            by: PermissionLedger.precedes
        ).map(\.state)
        core.state.sitePermissions[space] = records.isEmpty ? nil : records
        core.state.sitePermissionRevision &+= 1
        let change = SitePermissionsChanged(spaceID: space, records: records, touched: scopes)
        core.notificationAccessChanged()
        core.sitePermissionsChanged([change])
    }
    private func isPrivate(_ space: UUID) -> Bool {
        core.state.workspaces.values.contains { $0.kind.isPrivate && $0.spaces.contains(space) }
    }
    func shows(_ space: UUID, _ origin: SiteOrigin) -> Bool {
        PermissionLedger.valid(origin)
            && (origin.scheme == "https"
                || origin.scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(origin.host))
            && !isPrivate(space) && decision(space, origin, .notifications, nil).grants
    }
    func shows(_ profile: UUID, _ origin: SiteOrigin, _ source: ProfileNotificationSource) -> Bool {
        var owners: [UUID: WorkspaceModel] = [:]
        for workspace in core.state.workspaces.values.sorted(by: { $0.kind.ownsSpaces && !$1.kind.ownsSpaces }) {
            for space in workspace.spaces.models where space.profileID == profile && owners[space.id] == nil {
                owners[space.id] = workspace
            }
        }
        guard owners.count == 1, let (space, owner) = owners.first,
            !owner.spaceDeletions.contains(where: { $0.spaceID == space }), !isPrivate(space)
        else { return false }
        return source == .extension ? origin.scheme == "chrome-extension" && !origin.host.isEmpty : shows(space, origin)
    }
}

protocol SitePermissionIntent: Sendable {
    @MainActor func apply(to permissions: NativeSitePermissions) throws(PermissionFailure)
}
protocol SitePermissionQuery: Sendable {
    associatedtype Answer
    @MainActor func answer(from permissions: NativeSitePermissions) -> Answer
}
extension DecideSitePermission {
    @MainActor func apply(to permissions: NativeSitePermissions) throws(PermissionFailure) {
        try permissions.decide(self)
    }
}
extension ResetSitePermission {
    @MainActor func apply(to permissions: NativeSitePermissions) throws(PermissionFailure) {
        try permissions.reset(self)
    }
}
extension ResetSpacePermissions {
    @MainActor func apply(to permissions: NativeSitePermissions) throws(PermissionFailure) {
        try permissions.reset(self)
    }
}
extension AdoptSitePermissions {
    @MainActor func apply(to permissions: NativeSitePermissions) throws(PermissionFailure) {
        try permissions.adopt(records)
    }
}
extension SiteDecision {
    @MainActor func answer(from permissions: NativeSitePermissions) -> SitePermissionAnswer {
        SitePermissionAnswer(decision: permissions.decision(spaceID, origin, permission, detail))
    }
}
extension CaptureDecision {
    @MainActor func answer(from permissions: NativeSitePermissions) -> SitePermissionAnswer {
        SitePermissionAnswer(decision: permissions.mediaDecision(spaceID, origin, media))
    }
}
extension NotificationDisplayCheck {
    @MainActor func answer(from permissions: NativeSitePermissions) -> NotificationDisplayVerdict {
        NotificationDisplayVerdict(shows: permissions.shows(spaceID, origin))
    }
}
extension ProfileNotificationDisplayCheck {
    @MainActor func answer(from permissions: NativeSitePermissions) -> NotificationDisplayVerdict {
        NotificationDisplayVerdict(shows: permissions.shows(profileID, origin, source))
    }
}
extension CrestCore {
    func send(_ intent: some SitePermissionIntent) throws(PermissionFailure) { try permissions.send(intent) }
    func query<Q: SitePermissionQuery>(_ query: Q) throws(PermissionFailure) -> Q.Answer {
        drain()
        return query.answer(from: permissions)
    }
}
