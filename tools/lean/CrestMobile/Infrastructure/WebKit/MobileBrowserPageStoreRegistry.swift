import Foundation

@MainActor
final class MobileBrowserPageStoreRegistry: BrowserSpaceDataDeleting {
    private final class WeakStore {
        weak var value: MobileBrowserPageStore?

        init(_ value: MobileBrowserPageStore) {
            self.value = value
        }
    }

    private let primary: MobileBrowserPageStore
    private var stores: [ObjectIdentifier: WeakStore] = [:]
    /// Each window's private browsing, which memory pressure reaches and a
    /// Space's data deletion never does.
    private var privateStores: [ObjectIdentifier: WeakStore] = [:]
    private var spacesDeletingData: Set<UUID> = []

    init(primary: MobileBrowserPageStore) {
        self.primary = primary
    }

    func register(_ store: MobileBrowserPageStore) {
        stores[ObjectIdentifier(store)] = WeakStore(store)
    }

    func registerPrivateBrowsing(_ store: MobileBrowserPageStore) {
        privateStores[ObjectIdentifier(store)] = WeakStore(store)
    }

    func unregister(_ store: MobileBrowserPageStore) {
        stores.removeValue(forKey: ObjectIdentifier(store))
        privateStores.removeValue(forKey: ObjectIdentifier(store))
    }

    /// The primary store and every window's store still alive, private
    /// browsing included.
    var liveStores: [MobileBrowserPageStore] {
        stores = stores.filter { $0.value.value != nil }
        privateStores = privateStores.filter { $0.value.value != nil }
        return [primary]
            + (stores.values.compactMap(\.value) + privateStores.values.compactMap(\.value))
            .filter { $0 !== primary }
    }

    func deleteData(for space: BrowserSpaceRuntimeAssignment) async throws {
        guard spacesDeletingData.insert(space.spaceID).inserted else { return }
        defer { spacesDeletingData.remove(space.spaceID) }

        stores = stores.filter { $0.value.value != nil }
        let liveStores = stores.values.compactMap(\.value)
        for store in liveStores where store !== primary {
            await store.releaseWindowRuntime(for: space)
        }
        try await primary.deleteData(for: space)
    }
}
