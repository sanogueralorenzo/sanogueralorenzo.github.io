import Foundation

extension ReadSiteData {
    /// Lists the sites in the store the profile's pages use, or in its store
    /// on disk, without creating one the profile does not have.
    @MainActor func perform(on binding: WebKitEngineBinding) {
        let store = binding.existingStore(for: profileID, ephemeral: ephemeral)
        Task { [weak binding] in
            let sites =
                if let store = await store() { await BrowserWebsiteDataStore.storedSites(in: store) } else {
                    [StoredSite]()
                }
            binding?.report(SiteDataRead(readingID: readingID, sites: sites, read: true))
        }
    }
}
