#if CREST_CHROMIUM_HOST
    import Foundation

    extension WebNotificationClosed {
        @MainActor func present(on engine: ChromiumEngine) {
            engine.presentedPage(pageID)?.observer(BrowserPageWebNotificationClosed(notificationID: notificationID))
        }
    }
#endif
