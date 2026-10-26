#if CREST_CHROMIUM_HOST
    import Foundation

    extension PageNavigationCommitted {
        @MainActor func present(on engine: ChromiumEngine) {
            guard let page = engine.presentedPage(pageID) else { return }
            page.currentURL = URL(string: url)
            page.mediaSessionLocation = url
            page.surface.layoutEngineView()
            page.observer(BrowserPageNavigationCommitted(url: page.currentURL, isLoading: isLoading))
        }
    }
#endif
