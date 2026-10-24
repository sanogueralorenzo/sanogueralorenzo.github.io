import Foundation

extension EraseSiteData {
    /// Clears the site from the store the profile's pages use, or from its
    /// store on disk, without creating one the profile does not have.
    @MainActor func perform(on binding: WebKitEngineBinding) {
        let live = binding.memoryStores[profileID] ?? binding.liveStores[profileID]?.value
        Task { [weak binding] in
            guard let site = URL(string: "https://\(host)/") else {
                binding?.report(DataErased(erasureID: erasureID, erased: false))
                return
            }
            let onDisk = ephemeral || live != nil ? nil : await WebKitEngineBinding.storeOnDisk(for: profileID)
            if let store = live ?? onDisk { await BrowserWebsiteDataStore.clearSiteData(for: site, in: store) }
            binding?.report(DataErased(erasureID: erasureID, erased: true))
        }
    }
}
