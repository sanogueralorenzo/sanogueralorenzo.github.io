#if CREST_CHROMIUM_HOST
    import Foundation

    extension StoreRemovalRequested {
        @MainActor func present(on engine: ChromiumEngine) {
            engine.presentedPage(pageID)?.performStoreRequest(extensionID, removes: true)
        }
    }
#endif
