#if CREST_CHROMIUM_HOST
    import Foundation

    extension PageViewUnavailable {
        @MainActor func present(on engine: ChromiumEngine) {
            engine.presentedPage(pageID)?.observer(
                BrowserPageCreationFailed(message: String(localized: "Chromium couldn’t create this page.")))
        }
    }
#endif
