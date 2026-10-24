#if CREST_CHROMIUM_HOST
    import Foundation

    extension PageNavigationFailed {
        @MainActor func present(on engine: ChromiumEngine) {
            engine.presentedPage(pageID)?.observer(BrowserPageNavigationFailed())
        }
    }
#endif
