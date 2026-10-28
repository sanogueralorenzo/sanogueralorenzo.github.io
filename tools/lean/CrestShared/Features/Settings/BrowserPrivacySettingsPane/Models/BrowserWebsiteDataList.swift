import Foundation

/// The sites that keep data in one Space's engines, as the core lists them,
/// and removing them. Website data stays on this device: nothing here syncs.
@MainActor
@Observable
final class BrowserWebsiteDataList {
    // MARK: - Variables

    @ObservationIgnored private let core: CrestCore
    /// The Space's profile, whose stores the engines list.
    let profileID: UUID
    /// The profile keeps its data only in memory, as a private window's does.
    let ephemeral: Bool
    /// The sites, sorted by name, or nil until the first listing ends.
    private(set) var sites: [StoredSite]?
    /// Every engine listed its own sites; one that could not may hide some.
    private(set) var isComplete = true
    /// The last removal left something an engine could not clear.
    private(set) var removalFailed = false
    /// A removal is under way.
    private(set) var isRemoving = false

    // MARK: - Initializers

    init(core: CrestCore, profileID: UUID, ephemeral: Bool) {
        self.core = core
        self.profileID = profileID
        self.ephemeral = ephemeral
    }

    // MARK: - Actions - Listing

    /// Asks every engine again which sites keep data.
    func read() async {
        let read = await core.readWebsiteData(
            ReadWebsiteData(requestID: UUID(), profileID: profileID, ephemeral: ephemeral, host: nil))
        sites = read?.sites ?? sites ?? []
        isComplete = read?.complete ?? false
    }

    /// The sites whose names contain `query`, or every site for an empty one.
    func sites(matching query: String) -> [StoredSite] {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return sites ?? [] }
        return (sites ?? []).filter { $0.site.localizedStandardContains(query) }
    }

    // MARK: - Actions - Removing

    /// Removes everything `sites` keep in the Space, cookies, storage and
    /// cache alike, then lists the sites again.
    func remove(_ sites: [StoredSite]) async {
        guard !sites.isEmpty else { return }
        await removing(
            DeleteSiteData(
                requestID: UUID(), profileID: profileID, ephemeral: ephemeral, hosts: sites.map(\.site),
                categories: BrowsingDataCategory.all.filter(\.clearsBySite)))
    }

    /// Removes every site's data in the Space, a site no engine could list
    /// included, then lists the sites again.
    func removeAll() async {
        await removing(
            DeleteBrowsingData(
                requestID: UUID(), profileID: profileID, ephemeral: ephemeral, range: .allTime,
                categories: BrowsingDataCategory.all.filter(\.clearsBySite)))
    }

    private func removing(_ request: some DataDeletionRequest) async {
        guard !isRemoving else { return }
        isRemoving = true
        removalFailed = !(await core.deleteData(request))
        await read()
        isRemoving = false
    }
}
