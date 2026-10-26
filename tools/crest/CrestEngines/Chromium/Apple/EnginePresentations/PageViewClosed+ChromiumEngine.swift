#if CREST_CHROMIUM_HOST
    import Foundation

    extension PageViewClosed {
        @MainActor func present(on engine: ChromiumEngine) {
            engine.presentedPage(pageID)?.observer(BrowserPageClosedByEngine())
        }
    }
#endif
