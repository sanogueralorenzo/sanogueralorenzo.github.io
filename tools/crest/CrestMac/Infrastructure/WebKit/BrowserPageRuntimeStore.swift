import AppKit
import Observation
import WebKit

/// Normal windows share one page host while their pools keep independent
/// selection; this store decides which window presents each tab's page. A
/// temporary workspace receives its own store.
@Observable
@MainActor
final class BrowserPageRuntimeStore {
    private struct WeakPool {
        weak var value: BrowserPagePool?
    }

    /// The pages every window over the workspace shares.
    let host: BrowserPageHost
    @ObservationIgnored private var pools: [UUID: WeakPool] = [:]
    @ObservationIgnored private var presentations: [UUID: [UUID]] = [:]
    @ObservationIgnored private var focusOrder: [UUID: Int] = [:]
    @ObservationIgnored private var focusSequence = 0
    var publishesPageMetadataCentrally = false

    var runtimes: [UUID: BrowserTabRuntime] {
        get { host.runtimes }
        set { host.runtimes = newValue }
    }
    /// Moves whenever a tab gains or loses its page; see `BrowserPageHost`.
    var revision: Int {
        get { host.revision }
        set { host.revision = newValue }
    }
    var tabState: BrowserTabStateCoordinator { host.tabState }
    var nativeTabs: BrowserNativeTabStore { host.nativeTabs }

    init(archive: (any BrowserTabStateArchiving)? = nil) {
        host = BrowserPageHost(archive: archive)
        host.dropPresentation = { [weak self] in self?.removePresentation(of: $0) }
    }

    var registeredPools: [BrowserPagePool] { pools.values.compactMap(\.value) }

    var presentedTabIDs: Set<UUID> {
        Set(presentations.values.joined())
    }

    func isPresented(_ tabID: UUID, outside windowID: UUID) -> Bool {
        presentations.contains { $0.key != windowID && $0.value.contains(tabID) }
    }

    /// Registers `pool` as its window's, while that window is open. A pool
    /// that outlived its window never takes the place of the pool of the
    /// window reopened under its identity.
    func register(_ pool: BrowserPagePool) {
        guard pool.isWindowOpen else { return }
        pools[pool.windowID] = WeakPool(value: pool)
    }

    func updatePresentation(of pool: BrowserPagePool) {
        guard pool.isWindowOpen else { return }
        register(pool)
        presentations[pool.windowID] = pool.presentedTabIDs
        for tabID in pool.presentedTabIDs {
            if let runtime = runtimes[tabID],
                runtime.presentationWindowID == nil || pool.isWindowFocused
            {
                claim(tabID, for: pool)
            }
        }
        for (tabID, runtime) in runtimes
        where runtime.presentationWindowID == pool.windowID && !pool.presentedTabIDs.contains(tabID) {
            reassignPresentation(tabID, excluding: pool.windowID)
        }
    }

    func focus(_ pool: BrowserPagePool) {
        guard pool.isWindowOpen else { return }
        for other in registeredPools where other !== pool {
            other.setWindowFocused(false)
        }
        focusSequence &+= 1
        focusOrder[pool.windowID] = focusSequence
        updatePresentation(of: pool)
    }

    func claim(_ tabID: UUID, for pool: BrowserPagePool) {
        guard pool.isWindowOpen, pool.presentedTabIDs.contains(tabID), let runtime = runtimes[tabID] else { return }
        guard runtime.presentationWindowID != pool.windowID else {
            pool.bindRuntimeRouting(runtime, tabID: tabID)
            return
        }
        if runtime.presentationWindowID != nil {
            captureSnapshot(of: runtime)
            runtime.page.focusRestoration.captureBeforeDeparture()
            runtime.page.focusRestoration.requestRestoration()
        }
        runtime.presentationWindowID = pool.windowID
        runtime.routingWindowID = pool.windowID
        pool.bindRuntimeRouting(runtime, tabID: tabID)
    }

    /// Unregisters `pool`, when it is the pool registered for its window,
    /// and hands the pages it routed to the window focused most recently.
    func unregister(_ pool: BrowserPagePool) {
        guard pools[pool.windowID]?.value === pool else { return }
        presentations.removeValue(forKey: pool.windowID)
        pools.removeValue(forKey: pool.windowID)
        focusOrder.removeValue(forKey: pool.windowID)
        for (tabID, runtime) in runtimes where runtime.routingWindowID == pool.windowID {
            reassignPresentation(tabID, excluding: pool.windowID)
            if let fallback = mostRecentPool(among: Set(pools.keys)) {
                if runtime.presentationWindowID == nil {
                    runtime.routingWindowID = fallback.windowID
                    fallback.bindRuntimeRouting(runtime, tabID: tabID)
                }
            }
        }
    }

    func install(_ runtime: BrowserTabRuntime, for tabID: UUID, from pool: BrowserPagePool) {
        runtimes[tabID] = runtime
        runtime.store = self
        runtime.routingWindowID = pool.windowID
        pool.bindRuntimeRouting(runtime, tabID: tabID)
        updatePresentation(of: pool)
    }

    func removePresentation(of tabID: UUID) {
        for pool in registeredPools {
            pool.removeTransferredPresentation(tabID)
        }
    }

    private func reassignPresentation(_ tabID: UUID, excluding windowID: UUID) {
        guard let runtime = runtimes[tabID] else { return }
        let candidates = Set(
            presentations.compactMap { id, tabs in
                id != windowID && tabs.contains(tabID) ? id : nil
            })
        if let next = mostRecentPool(among: candidates) {
            claim(tabID, for: next)
        } else {
            runtime.presentationWindowID = nil
        }
    }

    private func mostRecentPool(among ids: Set<UUID>) -> BrowserPagePool? {
        ids.compactMap { pools[$0]?.value }.max {
            (focusOrder[$0.windowID] ?? 0) < (focusOrder[$1.windowID] ?? 0)
        }
    }

    private func captureSnapshot(of runtime: BrowserTabRuntime) {
        runtime.snapshotGeneration &+= 1
        let generation = runtime.snapshotGeneration
        runtime.page.captureViewport { [weak self, weak runtime] image in
            MainActor.assumeIsolated {
                guard let self, let runtime, runtime.store === self, runtime.snapshotGeneration == generation else {
                    return
                }
                if let image { runtime.snapshot = image }
            }
        }
    }
}

@MainActor
final class BrowserPageWindowRouting {
    weak var pool: BrowserPagePool?

    init(pool: BrowserPagePool) { self.pool = pool }
}
