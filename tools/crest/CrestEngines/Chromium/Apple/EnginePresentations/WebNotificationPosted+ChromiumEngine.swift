#if CREST_CHROMIUM_HOST
    import Foundation

    extension WebNotificationPosted {
        @MainActor func present(on engine: ChromiumEngine) {
            engine.presentedPage(pageID)?.observer(BrowserPageWebNotificationPosted(posted: self))
        }
    }
#endif
