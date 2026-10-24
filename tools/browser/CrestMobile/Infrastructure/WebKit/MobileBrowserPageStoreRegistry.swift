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
    private var spacesDeletingData: Set<UUID> = []

    init(primary: MobileBrowserPageStore) {
        self.primary = primary
    }

    func register(_ store: MobileBrowserPageStore) {
        stores[ObjectIdentifier(store)] = WeakStore(store)
    }

    func unregister(_ store: MobileBrowserPageStore) {
        stores.removeValue(forKey: ObjectIdentifier(store))
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
