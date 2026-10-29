import Foundation

/// The only owner of in-flight erasures and per-run profile-erasure proof.
/// Callers may cancel their UI tasks without abandoning privacy work.
@MainActor
final class NativeWebsiteData {
    private unowned let core: CrestCore
    private let now: @MainActor () -> Date
    private var active: [UUID: UUID] = [:]
    private var latest: [UUID: UUID] = [:]
    private var erased: Set<UUID> = []
    init(core: CrestCore, now: @escaping @MainActor () -> Date = Date.init) {
        self.core = core
        self.now = now
    }
    func isErasing(_ profile: UUID) -> Bool { active.values.contains(profile) }
    func hasErased(_ profile: UUID) -> Bool { erased.contains(profile) && !isErasing(profile) }
    var quitBarriers: [UUID] {
        var seen: Set<UUID> = []
        return core.state.workspaces.values.flatMap(\.spaceDeletions).filter { isErasing($0.profileID) }.map(\.spaceID)
            .filter { seen.insert($0).inserted }
    }
    /// Session commits still own operation IDs and persistence. Physical data
    /// proof is native and is checked on the common dispatch path, including
    /// generic SessionIntent callers. An unknown Space is the session's refusal.
    func validate(_ intent: some Intent) throws(Rejection) {
        guard let finish = intent as? FinishDeletingSpace else { return }
        core.drain()
        if let space = core.state.workspaces[finish.workspaceID]?.spaces.model(finish.spaceID),
            !hasErased(space.profileID)
        {
            throw .spaceDataNotErased(SpaceDataNotErased(spaceID: space.id))
        }
    }
    func delete(_ request: some DataDeletionRequest) async -> Bool {
        core.drain()
        guard let request = try? request.validated() else { return false }
        let attempt = UUID()
        if request.erasesProfile {
            erased.remove(request.profileID)
            latest[request.profileID] = attempt
            active[attempt] = request.profileID
        }
        let ended: Bool
        if let binding = core.engines.webKit {
            let date = now()
            // Unstructured, like Crest's original WebKit operation: cancelling
            // the caller does not cancel the erasure it already requested.
            ended = await Task { @MainActor in await request.erase(on: binding, at: date) }.value
        } else {
            ended = true
        }
        if request.erasesProfile {
            active[attempt] = nil
            if latest[request.profileID] == attempt && ended { erased.insert(request.profileID) }
        }
        core.notificationAccessChanged()
        return ended
    }
    func read(_ request: ReadWebsiteData) async -> WebsiteDataRead? {
        core.drain()
        guard (try? Self.host(request.host)) != nil || request.host == nil else { return nil }
        let raw: WebsiteDataRead
        if let binding = core.engines.webKit {
            raw = await Task { @MainActor in await request.read(on: binding) }.value
        } else {
            raw = WebsiteDataRead(sites: [], complete: true)
        }
        guard let sites = try? Self.normalize(raw.sites, host: request.host) else { return nil }
        return WebsiteDataRead(sites: sites, complete: raw.complete)
    }
    nonisolated static func siteName(_ value: String) -> String {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(
            in: CharacterSet(charactersIn: ".")
        ).lowercased()
        return name.hasPrefix("[") && name.hasSuffix("]") ? String(name.dropFirst().dropLast()) : name
    }
    private nonisolated static func host(_ raw: String?) throws(WebsiteDataFailure) -> String? {
        guard let raw else { return nil }
        let name = siteName(raw)
        guard (1...253).contains(name.utf16.count) else { throw .invalidSiteHost }
        return name
    }
    nonisolated static func normalize(_ sites: [StoredSite], host raw: String?) throws(WebsiteDataFailure)
        -> [StoredSite]
    {
        let host = try host(raw).map { Data($0.utf8) }
        var kept: [Data: StoredSite] = [:]
        for listed in sites {
            let name = siteName(listed.site)
            guard !name.isEmpty else { continue }
            let key = Data(name.utf8)
            if let host, host != key && !host.suffix(key.count + 1).elementsEqual(Data(("." + name).utf8)) { continue }
            let kinds = Set((kept[key]?.kinds ?? []) + listed.kinds)
            kept[key] = StoredSite(site: name, kinds: WebsiteDataKind.all.filter(kinds.contains))
        }
        return kept.values.sorted { $0.site.utf16.lexicographicallyPrecedes($1.site.utf16) }
    }
}
