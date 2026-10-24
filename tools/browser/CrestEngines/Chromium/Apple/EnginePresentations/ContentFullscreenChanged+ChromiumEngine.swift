#if CREST_CHROMIUM_HOST
    import Foundation

    extension ContentFullscreenChanged {
        @MainActor func present(on engine: ChromiumEngine) {
            engine.presentedPage(pageID)?.observer(BrowserPageContentFullscreenChanged(isActive: active))
        }
    }
#endif
