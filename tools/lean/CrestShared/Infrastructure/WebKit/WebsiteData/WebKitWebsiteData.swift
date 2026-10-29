import Foundation
import WebKit

extension DeleteProfileData {
    @MainActor func erase(on binding: WebKitEngineBinding, at now: Date) async -> Bool {
        binding.invalidateIntegrationSessions(profileID: profileID)
        do {
            try await binding.contentBlocking.removeData(
                profileID: profileID, isEphemeral: ephemeral || binding.keepsProfilesInMemory)
            binding.memoryStores[profileID] = nil
            if !ephemeral {
                try await binding.profileStores.removeProfile(BrowsingProfile(id: profileID), ephemeral: ephemeral)
            }
            return true
        } catch { return false }
    }
}
extension DeleteBrowsingData {
    @MainActor func erase(on binding: WebKitEngineBinding, at now: Date) async -> Bool {
        if let store = await binding.existingStore(for: profileID, ephemeral: ephemeral)() {
            await BrowserWebsiteDataStore.clear(categories, since: range.since(now), in: store)
        }
        return true
    }
}
extension DeleteSiteData {
    @MainActor func erase(on binding: WebKitEngineBinding, at now: Date) async -> Bool {
        let lookup = binding.existingStore(for: profileID, ephemeral: ephemeral)
        let pages = binding.pages.values.compactMap(\.value).filter { $0.profileID == profileID }
        guard let store = await lookup() else { return true }
        let erased = await BrowserWebsiteDataStore.clearSites(hosts, categories, in: store)
        if !store.isPersistent, categories.contains(.siteData) { await unregisterServiceWorkers(in: pages) }
        return erased
    }
    /// WebKit omits in-memory service workers from data records. Each matching
    /// page unregisters its own so they stop after the page reloads.
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
extension ReadWebsiteData {
    @MainActor func read(on binding: WebKitEngineBinding) async -> WebsiteDataRead {
        let sites: [StoredSite]
        if let store = await binding.existingStore(for: profileID, ephemeral: ephemeral)() {
            sites = await BrowserWebsiteDataStore.storedSites(in: store)
        } else {
            sites = []
        }
        return WebsiteDataRead(sites: sites, complete: true)
    }
}
