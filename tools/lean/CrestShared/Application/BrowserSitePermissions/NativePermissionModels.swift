import Foundation

struct AdoptSitePermissions: SitePermissionIntent, Equatable, Sendable {
    let records: Data?
}

struct DecideSitePermission: SitePermissionIntent, Equatable, Sendable {
    let spaceID: UUID
    let origin: SiteOrigin
    let permission: SitePermission
    let detail: String?
    let decision: SitePermissionDecision
}

struct ResetSitePermission: SitePermissionIntent, Equatable, Sendable {
    let recordID: UUID
}

struct ResetSpacePermissions: SitePermissionIntent, Equatable, Sendable {
    let spaceID: UUID
}

struct SiteDecision: SitePermissionQuery, Equatable, Sendable {
    typealias Answer = SitePermissionAnswer

    let spaceID: UUID
    let origin: SiteOrigin
    let permission: SitePermission
    let detail: String?
}

struct CaptureDecision: SitePermissionQuery, Equatable, Sendable {
    typealias Answer = SitePermissionAnswer

    let spaceID: UUID
    let origin: SiteOrigin
    let media: SitePermission
}

struct NotificationDisplayCheck: SitePermissionQuery, Equatable, Sendable {
    typealias Answer = NotificationDisplayVerdict

    let spaceID: UUID
    let origin: SiteOrigin
}

struct ProfileNotificationDisplayCheck: SitePermissionQuery, Equatable, Sendable {
    typealias Answer = NotificationDisplayVerdict

    let profileID: UUID
    let origin: SiteOrigin
    let source: ProfileNotificationSource
}

struct SitePermissionAnswer: Equatable, Sendable {
    let decision: SitePermissionDecision
}

struct NotificationDisplayVerdict: Equatable, Sendable {
    let shows: Bool
}

struct SitePermissionRecordState: Equatable, Sendable, Identifiable {
    let id: UUID
    let spaceID: UUID
    let origin: SiteOrigin
    let permission: SitePermission
    let detail: String?
    let decision: SitePermissionDecision
    var siteName: String { origin.displayName }
}

struct SitePermissionsChanged: Equatable, Sendable {
    let spaceID: UUID
    let records: [SitePermissionRecordState]
    let touched: [SitePermissionScope]
}

struct SitePermissionScope: Equatable, Sendable {
    let origin: SiteOrigin?
    let permission: SitePermission?
    let detail: String?
    let revokesAuthorization: Bool
}

enum ProfileNotificationSource: Int, CaseIterable, Sendable {
    case serviceWorker = 0
    case `extension` = 1
}
