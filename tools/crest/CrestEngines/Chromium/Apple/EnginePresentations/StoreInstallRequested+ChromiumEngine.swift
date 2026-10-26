#if CREST_CHROMIUM_HOST
    import Foundation

    extension StoreInstallRequested {
        @MainActor func present(on engine: ChromiumEngine) {
            engine.presentedPage(pageID)?.performStoreRequest(extensionID, removes: false)
        }
    }
#endif
