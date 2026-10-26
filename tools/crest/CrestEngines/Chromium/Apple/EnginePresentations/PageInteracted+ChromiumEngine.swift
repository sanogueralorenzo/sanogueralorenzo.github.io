#if CREST_CHROMIUM_HOST
    import Foundation

    extension PageInteracted {
        @MainActor func present(on engine: ChromiumEngine) {
            engine.presentedPage(pageID)?.observer(BrowserPageInteracted())
        }
    }
#endif
