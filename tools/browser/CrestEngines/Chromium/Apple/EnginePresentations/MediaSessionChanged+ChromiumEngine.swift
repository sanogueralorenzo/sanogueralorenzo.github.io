#if CREST_CHROMIUM_HOST
    import Foundation

    extension MediaSessionChanged {
        @MainActor func present(on engine: ChromiumEngine) {
            guard let page = engine.presentedPage(pageID), let event = BrowserMediaSessionPageEvent(self) else {
                return
            }
            page.observer(BrowserPageMediaSessionChanged(event: event))
        }
    }
#endif
