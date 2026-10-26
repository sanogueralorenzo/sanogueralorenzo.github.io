import Foundation

extension BrowserPlatformPage {
    /// Steps back through the page's history as the core keeps it, first
    /// leaving a failed navigation the page shows.
    func goBack() {
        refreshNavigationState()
        corePage.stepHistory(by: -1)
    }

    func goForward() {
        refreshNavigationState()
        corePage.stepHistory(by: 1)
    }

    /// The entries the page's back and forward menus list, nearest first, as
    /// the core keeps its history.
    var backHistory: [BrowserNavigationHistoryItem] { BrowserNavigationHistoryItem.listed(corePage.history.back) }
    var forwardHistory: [BrowserNavigationHistoryItem] { BrowserNavigationHistoryItem.listed(corePage.history.forward) }

    /// Returns to the entry a history menu offered.
    func goToHistory(_ item: BrowserNavigationHistoryItem) {
        corePage.showHistoryEntry(item.id)
    }

    /// Intercepted, same-document navigations have no didFinish callback.
    /// Retire their pending destination once the engine publishes that URL, and
    /// publish history from the same observation path as the address bar.
    func synchronizeNavigationHistory() {
        let currentEntryURL = pageEngine.synchronizeHistory()
        if pageEngine.currentURL == currentEntryURL { navigationReporter?.arrived(at: currentEntryURL) }
    }

    func reload() { enginePage.reload(bypassingCache: false) }

    /// Clears what the site the page shows keeps in `categories`, from every
    /// engine's store for the page's profile, not only the engine that shows
    /// it, then reloads the page from the network so it holds nothing it
    /// kept. Only memory is touched when the profile is `ephemeral`. Answers
    /// whether every engine cleared it, or nil when the page shows no site.
    func clearSiteData(_ categories: [BrowsingDataCategory], ephemeral: Bool) async -> Bool? {
        guard let targetURL = live.displayURL ?? pageEngine.currentURL, let host = targetURL.host(), !host.isEmpty
        else { return nil }
        let cleared = await corePage.eraseSiteData(
            hosts: [host], categories: categories, profileID: profileID, ephemeral: ephemeral)
        if pageEngine.currentURL == nil {
            corePage.load(targetURL)
        } else {
            enginePage.reload(bypassingCache: true)
        }
        return cleared
    }

    func performReload(_ mode: BrowserPageReloadMode) {
        mode.perform(on: enginePage, isLoading: live.isLoading)
    }

    func stopLoading() { enginePage.stop() }

    func retryAfterNavigationFailure() {
        guard let url = live.displayURL else { return }
        corePage.load(url)
    }

    var canProceedAfterCertificateFailure: Bool {
        live.failure?.error == .secureConnectionFailed
            && pendingServerTrustIdentity != nil
    }

    func proceedAfterCertificateFailure() {
        guard canProceedAfterCertificateFailure,
            let identity = pendingServerTrustIdentity
        else { return }
        serverTrustOverrides.approve(identity, for: profileID)
        retryAfterNavigationFailure()
    }

    /// Leaves the failure notice for the document behind it, or goes back
    /// past a failure that replaced the document.
    func returnFromNavigationFailure() {
        guard live.failure != nil else { return }
        corePage.stepHistory(by: -1)
    }

    var canReturnFromNavigationFailure: Bool { live.failure != nil && live.canGoBack }

    /// Forgets the URL Crest asked this page to load, once the engine has begun
    /// the navigation that honored it.
    ///
    /// The marker is a one-shot authorization. Leaving it in place would let web
    /// content replay the exact URL Crest once loaded — the one way past the gate
    /// that keeps `file:` destinations app-initiated.
    func consumeAppInitiatedURL() {
        appInitiatedURL = nil
    }
}
