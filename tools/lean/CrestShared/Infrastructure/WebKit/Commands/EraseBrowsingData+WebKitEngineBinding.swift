import Foundation

extension EraseBrowsingData {
    /// Clears what changed since `since` in the store the profile's pages use,
    /// or in its store on disk, without creating one the profile does not
    /// have. A profile with no store has nothing to clear.
    @MainActor func perform(on binding: WebKitEngineBinding) {
        let store = binding.existingStore(for: profileID, ephemeral: ephemeral)
        Task { [weak binding] in
            if let store = await store() {
                await BrowserWebsiteDataStore.clear(categories, since: since, in: store)
            }
            binding?.report(DataErased(erasureID: erasureID, erased: true))
        }
    }
}
