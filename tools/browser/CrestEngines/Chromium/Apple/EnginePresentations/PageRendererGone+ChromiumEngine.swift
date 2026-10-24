#if CREST_CHROMIUM_HOST
    import Foundation

    extension PageRendererGone {
        @MainActor func present(on engine: ChromiumEngine) {
            engine.presentedPage(pageID)?.observer(BrowserPageContentProcessTerminated())
        }
    }
#endif
