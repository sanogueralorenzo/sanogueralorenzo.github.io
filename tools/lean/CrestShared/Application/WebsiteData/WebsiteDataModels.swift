import Foundation

struct DeleteProfileData: DataDeletionRequest, Equatable, Sendable {
    let profileID: UUID
    let ephemeral: Bool
}

struct DeleteSiteData: DataDeletionRequest, Equatable, Sendable {
    let profileID: UUID
    let ephemeral: Bool
    let hosts: [String]
    let categories: [BrowsingDataCategory]
}

struct DeleteBrowsingData: DataDeletionRequest, Equatable, Sendable {
    let profileID: UUID
    let ephemeral: Bool
    let range: BrowsingDataRange
    let categories: [BrowsingDataCategory]
}

struct ReadWebsiteData: Equatable, Sendable {
    let profileID: UUID
    let ephemeral: Bool
    let host: String?
}

struct StoredSite: Equatable, Sendable {
    var site: String
    var kinds: [WebsiteDataKind]
}

struct WebsiteDataRead: Equatable, Sendable {
    let sites: [StoredSite]
    let complete: Bool
}
