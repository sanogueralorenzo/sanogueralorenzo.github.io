#if CREST_CHROMIUM_HOST
    import Foundation

    extension PageNavigationStarted {
        @MainActor func present(on engine: ChromiumEngine) {
            engine.presentedPage(pageID)?.observer(BrowserPageNavigationStarted())
        }
    }
#endif
