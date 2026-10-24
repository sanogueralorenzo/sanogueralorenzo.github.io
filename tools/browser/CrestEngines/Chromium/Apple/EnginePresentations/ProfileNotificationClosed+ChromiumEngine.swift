#if CREST_CHROMIUM_HOST
    import Foundation

    extension ProfileNotificationClosed {
        @MainActor func present(on engine: ChromiumEngine) {
            engine.notifications?.withdraw(profileID: profileID, notificationID: notificationID)
        }
    }
#endif
