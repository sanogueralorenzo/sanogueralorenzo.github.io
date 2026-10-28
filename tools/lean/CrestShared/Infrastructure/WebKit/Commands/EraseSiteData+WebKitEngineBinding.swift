import Foundation
import WebKit

extension EraseSiteData {
    /// Clears the sites' data in its categories from the store the profile's
    /// pages use, or from its store on disk, without creating one the profile
    /// does not have. A profile with no store has nothing to clear.
    @MainActor func perform(on binding: WebKitEngineBinding) {
        let store = binding.existingStore(for: profileID, ephemeral: ephemeral)
        let pages = binding.pages.values.compactMap(\.value).filter { $0.profileID == profileID }
        Task { [weak binding] in
            let erased: Bool
            if let store = await store() {
                erased = await BrowserWebsiteDataStore.clearSites(hosts, categories, in: store)
                if !store.isPersistent, categories.contains(.siteData) { await unregisterServiceWorkers(in: pages) }
            } else {
                erased = true
            }
            binding?.report(DataErased(erasureID: erasureID, erased: erased))
        }
    }

    /// WebKit leaves a store in memory's service workers out of its data
    /// records, so clearing the store never reaches them. Each of the
    /// profile's pages that shows one of the sites unregisters its own
    /// instead, which stops them once the page reloads.
    @MainActor private func unregisterServiceWorkers(in pages: [WebKitEnginePage]) async {
        let script = """
            const registrations = await navigator.serviceWorker?.getRegistrations?.() ?? [];
            await Promise.all(registrations.map(registration => registration.unregister()));
            """
        for page in pages {
            guard let host = page.webView.url?.host(),
                hosts.contains(where: { BrowserWebsiteDataStore.matchesDataRecord(displayName: $0, host: host) })
            else { continue }
            _ = try? await page.webView.callAsyncJavaScript(script, contentWorld: .page)
        }
    }
}
