#if CREST_CHROMIUM_HOST
    import Foundation

    extension LinkHovered {
        @MainActor func present(on engine: ChromiumEngine) {
            engine.presentedPage(pageID)?.observer(BrowserPageLinkHovered(destination: url.flatMap(URL.init(string:))))
        }
    }
#endif
