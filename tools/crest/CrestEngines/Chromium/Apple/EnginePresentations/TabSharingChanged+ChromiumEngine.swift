#if CREST_CHROMIUM_HOST
    import Foundation

    extension TabSharingChanged {
        @MainActor func present(on engine: ChromiumEngine) {
            engine.presentedPage(pageID)?.observer(BrowserPageTabSharingChanged(shared: shared, sharing: sharing))
        }
    }
#endif
