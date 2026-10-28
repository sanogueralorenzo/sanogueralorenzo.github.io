import Foundation
import WebKit

@MainActor
enum BrowserWebsiteDataStore {
    // MARK: - Static Variables

    /// The data types WebKit keeps to load sites faster, which clearing the
    /// cache removes and clearing site data leaves.
    private static let cacheTypes: Set<String> = [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache]

    /// What WebKit's types are, as the website data list names them. A type
    /// that is not a site's own data, such as Screen Time's, names nothing.
    private static let kinds: [String: WebsiteDataKind] = [
        WKWebsiteDataTypeCookies: .cookies,
        WKWebsiteDataTypeDiskCache: .cache,
        WKWebsiteDataTypeMemoryCache: .cache,
        WKWebsiteDataTypeFetchCache: .storage,
        WKWebsiteDataTypeSessionStorage: .storage,
        WKWebsiteDataTypeLocalStorage: .storage,
        WKWebsiteDataTypeWebSQLDatabases: .storage,
        WKWebsiteDataTypeIndexedDBDatabases: .storage,
        WKWebsiteDataTypeServiceWorkerRegistrations: .storage,
        WKWebsiteDataTypeFileSystem: .storage,
        WKWebsiteDataTypeMediaKeys: .storage,
        WKWebsiteDataTypeHashSalt: .storage,
    ]

    /// Where a cookie's properties name the top-level site it is partitioned
    /// under, as `scheme://site`, for one a third party set while embedded in
    /// that site. WebKit has no public constant for it; a cookie without it is
    /// partitioned under no site.
    private static let storagePartitionKey = HTTPCookiePropertyKey("StoragePartition")

    /// The data types each category of browsing data covers in WebKit, which
    /// keeps no record of visits.
    private static let categoryTypes: [BrowsingDataCategory: Set<String>] = [
        .history: [],
        .siteData: WKWebsiteDataStore.allWebsiteDataTypes().subtracting(cacheTypes),
        .cache: cacheTypes,
    ]

    // MARK: - Actions - Stores

    static func launchScoped(
        for profile: BrowsingProfile,
        environment: BrowserLaunchEnvironment = .current
    ) -> WKWebsiteDataStore {
        guard
            !environment.usesEphemeralProfileStorage
        else {
            return .nonPersistent()
        }
        return persistent(for: profile, environment: environment)
    }

    /// The profile's persistent store, which a named isolated launch keeps
    /// apart from the installed app's.
    static func persistent(
        for profile: BrowsingProfile,
        environment: BrowserLaunchEnvironment = .current
    ) -> WKWebsiteDataStore {
        WKWebsiteDataStore(forIdentifier: environment.websiteDataStoreIdentifier(forProfileID: profile.id))
    }

    /// `dataStore` and, for one on disk, the obsolete store that copied its
    /// cookies for extensions, when that one still exists.
    private static func storesClearing(_ dataStore: WKWebsiteDataStore) async -> [WKWebsiteDataStore] {
        guard let identifier = dataStore.identifier else { return [dataStore] }
        let hostedID = BrowserLegacyExtensionWebsiteDataStore.identifier(forProfileID: identifier)
        guard await WKWebsiteDataStore.allDataStoreIdentifiers.contains(hostedID) else { return [dataStore] }
        return [dataStore, WKWebsiteDataStore(forIdentifier: hostedID)]
    }

    // MARK: - Actions - Clearing

    /// Clears what the sites of `hosts` keep in `dataStore` in `categories`:
    /// their cookies, storage and service workers, their cache, or both, by
    /// the registrable domain WebKit groups them under. Answers whether the
    /// cookies it removed are gone; WebKit reports nothing about the rest.
    static func clearSites(
        _ hosts: [String], _ categories: [BrowsingDataCategory], in dataStore: WKWebsiteDataStore
    ) async -> Bool {
        let hosts = hosts.map(normalizedHost).filter { !$0.isEmpty }
        let dataTypes = types(of: categories)
        guard !hosts.isEmpty, !dataTypes.isEmpty else { return false }
        var cleared = true
        for store in await storesClearing(dataStore) {
            cleared = await clearSites(hosts, dataTypes, inStore: store) && cleared
        }
        return cleared
    }

    private static func clearSites(_ hosts: [String], _ dataTypes: Set<String>, inStore dataStore: WKWebsiteDataStore)
        async -> Bool
    {
        let records = await dataRecords(ofTypes: dataTypes, in: dataStore).filter { record in
            hosts.contains { matchesDataRecord(displayName: record.displayName, host: $0) }
        }
        // A record names the registrable domain, so its subdomains' cookies
        // go with it, beside the cookies each host and its parents set, and
        // those third parties set while embedded in one of them.
        let sites = hosts + records.map(\.displayName)
        let cookieStore = dataStore.httpCookieStore
        let removed =
            dataTypes.contains(WKWebsiteDataTypeCookies)
            ? await allCookies(in: cookieStore).filter { cookie in
                let partition = partitionHost(of: cookie)
                return sites.contains { site in
                    includesCookieDomainForRemoval(cookie.domain, host: site) || isSubdomain(cookie.domain, of: site)
                        || partition.map { $0 == normalizedHost(site) || isSubdomain($0, of: site) } == true
                }
            } : []
        for cookie in removed { await delete(cookie, from: cookieStore) }
        if !records.isEmpty { await removeData(ofTypes: dataTypes, for: records, in: dataStore) }
        guard !removed.isEmpty else { return true }
        let remaining = Set(await allCookies(in: cookieStore).map(CookieIdentity.init))
        return removed.allSatisfy { !remaining.contains(CookieIdentity($0)) }
    }

    /// Clears what changed in `dataStore` since `since`, or ever when it is
    /// nil, in `categories`. WebKit hosts no extensions, so all of it is web data.
    static func clear(_ categories: [BrowsingDataCategory], since: Date?, in dataStore: WKWebsiteDataStore) async {
        let dataTypes = types(of: categories)
        guard !dataTypes.isEmpty else { return }
        for store in await storesClearing(dataStore) {
            await withCheckedContinuation { continuation in
                store.removeData(ofTypes: dataTypes, modifiedSince: since ?? .distantPast) { continuation.resume() }
            }
        }
    }

    /// The WebKit data types `categories` cover.
    private static func types(of categories: [BrowsingDataCategory]) -> Set<String> {
        categories.reduce(into: Set<String>()) { $0.formUnion(categoryTypes[$1] ?? []) }
    }

    // MARK: - Actions - Listing

    /// The sites that keep data in `dataStore`, by the registrable domain
    /// WebKit groups them under, with the kinds each keeps.
    static func storedSites(in dataStore: WKWebsiteDataStore) async -> [StoredSite] {
        await dataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), in: dataStore).compactMap { record in
            let kept = Set(record.dataTypes.compactMap { kinds[$0] })
            guard !kept.isEmpty else { return nil }
            return StoredSite(site: record.displayName, kinds: WebsiteDataKind.all.filter(kept.contains))
        }
    }

    // MARK: - Actions - Matching

    /// Whether a website data record named `displayName` belongs to `host`:
    /// the host itself, a parent of it, or a subdomain of it.
    nonisolated static func matchesDataRecord(displayName: String, host: String) -> Bool {
        let record = normalizedHost(displayName)
        let host = normalizedHost(host)
        guard !record.isEmpty, !host.isEmpty else { return false }
        return record == host
            || host.hasSuffix(".\(record)")
            || record.hasSuffix(".\(host)")
    }

    /// Site-data deletion intentionally includes parent domains. This is not
    /// request eligibility: it does not model host-only, Secure, path or SameSite.
    nonisolated static func includesCookieDomainForRemoval(_ domain: String, host: String) -> Bool {
        let domain = normalizedHost(domain)
        let host = normalizedHost(host)
        guard !domain.isEmpty, !host.isEmpty else { return false }
        return domain == host || host.hasSuffix(".\(domain)")
    }

    /// The host of the top-level site `cookie` is partitioned under, or nil
    /// for a cookie that is not partitioned.
    private static func partitionHost(of cookie: HTTPCookie) -> String? {
        guard let partition = cookie.properties?[storagePartitionKey] as? String,
            let host = URL(string: partition)?.host(), !host.isEmpty
        else { return nil }
        return normalizedHost(host)
    }

    /// Whether a cookie set on `domain` belongs to a subdomain of `site`.
    private nonisolated static func isSubdomain(_ domain: String, of site: String) -> Bool {
        let domain = normalizedHost(domain)
        let site = normalizedHost(site)
        return !site.isEmpty && domain.hasSuffix(".\(site)")
    }

    private nonisolated static func normalizedHost(_ value: String) -> String {
        value.lowercased().trimmingCharacters(
            in: CharacterSet(charactersIn: ".")
        )
    }

    // MARK: - Actions - WebKit

    private static func allCookies(
        in cookieStore: WKHTTPCookieStore
    ) async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            cookieStore.getAllCookies { continuation.resume(returning: $0) }
        }
    }

    private static func delete(
        _ cookie: HTTPCookie,
        from cookieStore: WKHTTPCookieStore
    ) async {
        await withCheckedContinuation { continuation in
            cookieStore.delete(cookie) { continuation.resume() }
        }
    }

    private static func dataRecords(
        ofTypes dataTypes: Set<String>,
        in dataStore: WKWebsiteDataStore
    ) async -> [WKWebsiteDataRecord] {
        await withCheckedContinuation { continuation in
            dataStore.fetchDataRecords(ofTypes: dataTypes) {
                continuation.resume(returning: $0)
            }
        }
    }

    private static func removeData(
        ofTypes dataTypes: Set<String>,
        for records: [WKWebsiteDataRecord],
        in dataStore: WKWebsiteDataStore
    ) async {
        await withCheckedContinuation { continuation in
            dataStore.removeData(ofTypes: dataTypes, for: records) {
                continuation.resume()
            }
        }
    }
}

/// One cookie as a store keeps it, so a cookie that survived its deletion is
/// told apart from one a page set again since.
private struct CookieIdentity: Hashable {
    let name: String
    let domain: String
    let path: String
    let value: String

    init(_ cookie: HTTPCookie) {
        name = cookie.name
        domain = cookie.domain.lowercased()
        path = cookie.path
        value = cookie.value
    }
}
