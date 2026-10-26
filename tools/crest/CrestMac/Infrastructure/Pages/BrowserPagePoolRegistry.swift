import Foundation

@MainActor
final class BrowserPagePoolRegistry: BrowserSpaceDataDeleting {

    private final class WeakPool {
        weak var value: BrowserPagePool?

        init(_ value: BrowserPagePool) {
            self.value = value
        }
    }

    private final class WeakWindowRuntime {
        weak var browser: BrowserStore?
        weak var pages: BrowserPagePool?

        init(browser: BrowserStore, pages: BrowserPagePool) {
            self.browser = browser
            self.pages = pages
        }
    }

    private weak var spaceAccess: BrowserSpaceAccessController?
    private let primary: BrowserPagePool
    private var pools: [ObjectIdentifier: WeakPool] = [:]
    private var windowRuntimes: [UUID: WeakWindowRuntime] = [:]
    private var spacesDeletingData: Set<UUID> = []

    init(primary: BrowserPagePool, spaceAccess: BrowserSpaceAccessController? = nil) {
        self.primary = primary
        self.spaceAccess = spaceAccess
    }

    func register(_ pool: BrowserPagePool) {
        pools[ObjectIdentifier(pool)] = WeakPool(pool)
    }

    /// Registers `pool` as the pages of window `windowID`, which `browser`
    /// is while it is open.
    func register(
        _ pool: BrowserPagePool,
        browser: BrowserStore,
        for windowID: UUID
    ) {
        guard browser.isOpen(as: windowID) else { return }
        register(pool)
        browser.family.pageDismissalAuthorizer = self
        windowRuntimes[windowID] = WeakWindowRuntime(
            browser: browser,
            pages: pool
        )
    }

    func unregister(_ pool: BrowserPagePool) {
        pools.removeValue(forKey: ObjectIdentifier(pool))
    }

    /// Unregisters `pool` as the pages of window `windowID`, leaving the
    /// pages of a window since opened under that identity in place.
    func unregister(_ pool: BrowserPagePool, for windowID: UUID) {
        unregister(pool)
        guard windowRuntimes[windowID]?.pages === pool else { return }
        windowRuntimes.removeValue(forKey: windowID)
    }

    /// The primary pool and every other pool still registered.
    var livePools: [BrowserPagePool] {
        pools = pools.filter { $0.value.value != nil }
        return [primary] + pools.values.compactMap(\.value).filter { $0 !== primary }
    }

    func runtime(for windowID: UUID) -> BrowserPagePoolWindowRuntime? {
        guard let runtime = windowRuntimes[windowID],
            let browser = runtime.browser,
            let pages = runtime.pages
        else {
            windowRuntimes.removeValue(forKey: windowID)
            return nil
        }
        return BrowserPagePoolWindowRuntime(browser: browser, pages: pages)
    }

    /// Releases every window's pages in the Space, then its data. The Space's
    /// deletion is already recorded in the session, so the core opens no new
    /// page there while this runs.
    func deleteData(for space: BrowserSpaceRuntimeAssignment) async throws {
        guard spacesDeletingData.insert(space.spaceID).inserted else { return }
        defer { spacesDeletingData.remove(space.spaceID) }

        for pool in livePools where pool !== primary {
            await pool.releaseWindowRuntime(for: space)
        }
        try await primary.deleteData(for: space)
    }
}

extension BrowserPagePoolRegistry: BrowserPageDismissalAuthorizing {
    func performDismissal(
        of assignments: [BrowserTabRuntimeAssignment], in browser: BrowserStore,
        operation: @escaping @MainActor () -> Bool
    ) -> Bool {
        func ownedPages() -> [BrowserPage] {
            var seen = Set<ObjectIdentifier>()
            return windowRuntimes.values.compactMap { runtime -> BrowserPagePool? in
                runtime.browser?.family === browser.family ? runtime.pages : nil
            }.flatMap { pool in assignments.compactMap { pool.residentPage(matching: $0) } }
                .filter { seen.insert(ObjectIdentifier($0)).inserted }
        }
        func isAvailable() -> Bool {
            assignments.allSatisfy { assignment in
                guard let space = browser.spaceModel(matching: assignment.spaceAssignment),
                    !spacesDeletingData.contains(space.id)
                else { return false }
                return spaceAccess?.isLocked(space) != true
            }
        }
        guard isAvailable() else { return false }
        let pages = ownedPages()
        guard !pages.isEmpty else { return operation() }
        let identities = Set(pages.map { ObjectIdentifier($0) })
        var committed = false
        // The core asks each page in turn whether it may go. A page that needs
        // no answer lets the core finish at once, so the dismissal commits
        // before this returns; one that asks the person commits later.
        let request = PrepareToClosePages(requestID: UUID(), pageIDs: pages.map(\.corePage.id))
        browser.core.prepareToClose(request) { [weak self, weak browser] allowed in
            guard let self, let browser, allowed, isAvailable(),
                Set(ownedPages().map { ObjectIdentifier($0) }) == identities
            else { return }
            committed = operation()
            guard committed else { return }
            for runtime in self.windowRuntimes.values where runtime.browser?.family === browser.family {
                guard runtime.browser != nil, let pool = runtime.pages else { continue }
                pool.reconcile()
                pool.select()
            }
        }
        return committed
    }
}
