#if CREST_CHROMIUM_HOST
    import Foundation

    extension PageLoadingChanged {
        @MainActor func present(on engine: ChromiumEngine) {
            guard let page = engine.presentedPage(pageID) else { return }
            page.observer(BrowserPageLoadingChanged(isLoading: isLoading))
            page.observer(BrowserPageProgressChanged(progress: isLoading ? 0.5 : 1))
        }
    }
#endif
