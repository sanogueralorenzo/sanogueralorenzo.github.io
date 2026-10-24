#if CREST_CHROMIUM_HOST
    import Foundation

    extension ProfileNotificationPosted {
        @MainActor func present(on engine: ChromiumEngine) {
            engine.notifications?.show(self)
        }
    }
#endif
