#if CREST_CHROMIUM_HOST
    import Foundation

    extension PageViewReady {
        @MainActor func present(on engine: ChromiumEngine) {
            engine.presentedPage(pageID)?.viewReady()
        }
    }
#endif
