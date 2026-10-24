import Foundation

/// Keeps one open page's engine in step with Crest's per-Space site permission
/// records, whichever engine hosts it, over the page's `EnginePage`.
///
/// The core decides every answer through `BrowserSitePermissionCenter`; this
/// session only carries the answers to the page. A change made anywhere — the
/// page's own prompt, Site Controls, or the Privacy pane — reaches the page at
/// once rather than on its next navigation:
///
/// - An engine that enforces site permissions itself is told the decision for
///   the page's site.
/// - Camera or microphone capture the page was granted is stopped when that
///   grant is withdrawn.
/// - `siteDecisionDidChange` runs for each affected permission, so bridges Crest
///   runs inside the page can refresh what the document sees.
@MainActor
final class BrowserPageSitePermissionSession: BrowserSitePermissionObserver {
    // MARK: - Types

    private struct MediaGrant: Hashable {
        let permission: SitePermission
        let origin: SiteOrigin
    }

    // MARK: - Variables

    /// The permissions an engine may enforce itself. Crest's per-Space record
    /// decides them and the engine is told the answer.
    static let engineEnforcedPermissions = SitePermission.all.filter(\.isEngineEnforced)

    /// The permissions whose changes the page is told about.
    private static let observedPermissions: [SitePermission] = engineEnforcedPermissions + [.popups]

    /// The URL of the document the page shows, whose site the engine applies
    /// decisions to.
    var siteURL: @MainActor () -> URL? = { nil }

    /// Runs after a change affected one of the observed permissions for the
    /// page's site.
    var siteDecisionDidChange: @MainActor (SitePermission) -> Void = { _ in }

    private let page: EnginePage
    private let permissionCenter: BrowserSitePermissionCenter
    private let spaceID: UUID
    private var mediaGrants: [MediaGrant: SitePermissionDecision] = [:]

    // MARK: - Initializers

    init(page: EnginePage, permissionCenter: BrowserSitePermissionCenter, spaceID: UUID) {
        self.page = page
        self.permissionCenter = permissionCenter
        self.spaceID = spaceID
        permissionCenter.addObserver(self)
    }

    // MARK: - Actions - Media capture

    /// Remembers capture the page was allowed, with the decision that allowed
    /// it, so a later withdrawal of that decision ends the capture.
    func recordMediaGrant(_ permission: SitePermission, origin: SiteOrigin) {
        mediaGrants[MediaGrant(permission: permission, origin: origin)] = permissionCenter.mediaDecision(
            for: permission, origin: origin, in: spaceID)
    }

    /// Forgets capture grants; the document that held them is going away.
    func resetMediaGrants() {
        mediaGrants.removeAll()
    }

    private func revokeChangedMediaGrants() {
        for (grant, previous) in mediaGrants {
            let decision = permissionCenter.mediaDecision(for: grant.permission, origin: grant.origin, in: spaceID)
            guard decision != previous else { continue }
            if decision.grants {
                mediaGrants[grant] = decision
                continue
            }
            mediaGrants.removeValue(forKey: grant)
            page.stopCapture(grant.permission)
        }
    }

    // MARK: - Actions - Engine-enforced permissions

    /// Applies Crest's record for `url`'s site, or the page's current site, to
    /// an engine that enforces site permissions itself.
    func synchronize(for url: URL? = nil) {
        guard let origin = (url ?? siteURL()).flatMap(SiteOrigin.init(url:)) else { return }
        for permission in Self.engineEnforcedPermissions {
            apply(permission, origin: origin)
        }
    }

    /// A device without its own answer follows a combined capture record.
    private func apply(_ permission: SitePermission, origin: SiteOrigin) {
        let decision = ([permission] + permission.combinations).lazy
            .map { self.permissionCenter.decision(for: $0, origin: origin, in: self.spaceID) }
            .first { $0.verdict != .ask }
        page.setSitePermission(permission, allowed: decision?.grants)
    }

    private func affects(
        _ change: BrowserSitePermissionChange,
        _ permission: SitePermission,
        origin: SiteOrigin
    ) -> Bool {
        // A combined capture record answers each of its devices.
        ([permission] + permission.combinations).contains { change.affects($0, origin: origin, in: spaceID) }
    }

    // MARK: - Actions - Observation

    func sitePermissionsDidChange(_ change: BrowserSitePermissionChange) {
        revokeChangedMediaGrants()
        guard let origin = siteURL().flatMap(SiteOrigin.init(url:)) else { return }
        for permission in Self.observedPermissions where affects(change, permission, origin: origin) {
            if Self.engineEnforcedPermissions.contains(permission) {
                apply(permission, origin: origin)
            }
            siteDecisionDidChange(permission)
        }
    }
}
