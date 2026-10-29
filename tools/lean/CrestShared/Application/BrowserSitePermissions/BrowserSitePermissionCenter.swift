import Foundation

struct BrowserSitePermissionChange {
    var spaceID: UUID?
    var origin: SiteOrigin?
    var permission: SitePermission?
    var detail: String?
    var revokesAuthorization: Bool

    func affects(_ permission: SitePermission, origin: SiteOrigin, in spaceID: UUID) -> Bool {
        (self.spaceID == nil || self.spaceID == spaceID)
            && (self.origin == nil || self.origin == origin)
            && (self.permission == nil || self.permission == permission)
            && detail == nil
    }
}

@MainActor
protocol BrowserSitePermissionObserver: AnyObject {
    func sitePermissionsDidChange(_ change: BrowserSitePermissionChange)
}

@MainActor
final class BrowserSitePermissionCenter {
    // MARK: - Static Variables

    private static let log = DiagnosticLog.sitePermissions

    // MARK: - Types

    private struct Observer {
        weak var value: (any BrowserSitePermissionObserver)?
    }

    // MARK: - Variables

    private let core: CrestCore
    private var observers: [Observer] = []

    // MARK: - Initializers

    /// A center over `core`, whose changes it passes to its observers.
    init(core: CrestCore) {
        self.core = core
        core.followSitePermissions(self) { [weak self] change in self?.changed(change) }
    }

    /// A center over a memory-only core of its own, as previews, practice
    /// pages and tests use, which keeps nothing.
    convenience init() {
        self.init(core: CrestCore())
    }

    // MARK: - Actions - Adoption

    /// Carries the document an installed release kept under
    /// `crest.site-permissions.v1` into the native permission store, once, and
    /// seeds the read model with every Space's kept choices.
    func adoptLegacyRecords(_ document: Data?) {
        do {
            try core.send(AdoptSitePermissions(records: document))
        } catch {
            Self.log.error(
                "Could not adopt the saved site permissions: \(DiagnosticLog.describe(error))")
        }
    }

    // MARK: - Actions - Decisions

    /// The choice that applies to one request. `detail` narrows a capability a
    /// site can ask for more than one way.
    func decision(
        for permission: SitePermission,
        origin: SiteOrigin,
        detail: String? = nil,
        in spaceID: UUID
    ) -> SitePermissionDecision {
        _ = core.state.sitePermissionRevision
        let question = SiteDecision(
            spaceID: spaceID, origin: origin, permission: permission, detail: detail)
        return (try? core.query(question))?.decision ?? .ask
    }

    /// Combined capture must respect a block on either device.
    func mediaDecision(
        for media: SitePermission,
        origin: SiteOrigin,
        in spaceID: UUID
    ) -> SitePermissionDecision {
        _ = core.state.sitePermissionRevision
        let question = CaptureDecision(spaceID: spaceID, origin: origin, media: media)
        return (try? core.query(question))?.decision ?? .ask
    }

    /// Whether a notification a document at `origin` posted in a page of the
    /// Space shows now. An unavailable core shows none.
    func showsNotification(from origin: SiteOrigin, in spaceID: UUID) -> Bool {
        _ = core.state.sitePermissionRevision
        return (try? core.query(NotificationDisplayCheck(spaceID: spaceID, origin: origin)))?.shows ?? false
    }

    /// The choices a Space keeps, in the order the settings list them.
    func records(in spaceID: UUID) -> [SitePermissionRecordState] {
        core.state.sitePermissions[spaceID] ?? []
    }

    // MARK: - Actions - Observers

    /// Authorization withdrawal must be synchronous: observation can coalesce
    /// a reset followed by a new grant, leaving old requests authorized.
    func addObserver(_ observer: any BrowserSitePermissionObserver) {
        observers.removeAll { $0.value == nil || $0.value === observer }
        observers.append(Observer(value: observer))
    }

    /// Tells each observer what one applied change covered.
    private func changed(_ change: SitePermissionsChanged) {
        observers.removeAll { $0.value == nil }
        let current = observers.compactMap(\.value)
        for scope in change.touched {
            let touched = BrowserSitePermissionChange(
                spaceID: change.spaceID, origin: scope.origin,
                permission: scope.permission, detail: scope.detail, revokesAuthorization: scope.revokesAuthorization)
            for observer in current { observer.sitePermissionsDidChange(touched) }
        }
    }

    // MARK: - Actions - Changes

    func setDecision(
        _ decision: SitePermissionDecision,
        for permission: SitePermission,
        origin: SiteOrigin,
        detail: String? = nil,
        in spaceID: UUID
    ) {
        send(
            DecideSitePermission(
                spaceID: spaceID, origin: origin, permission: permission, detail: detail,
                decision: decision))
    }

    func reset(recordID: UUID) {
        send(ResetSitePermission(recordID: recordID))
    }

    func reset(spaceID: UUID) {
        send(ResetSpacePermissions(spaceID: spaceID))
    }

    private func send(_ intent: some SitePermissionIntent) {
        do {
            try core.send(intent)
        } catch {
            Self.log.notice(
                "Permission rules refused \(String(describing: type(of: intent))): \(DiagnosticLog.describe(error))"
            )
        }
    }
}
