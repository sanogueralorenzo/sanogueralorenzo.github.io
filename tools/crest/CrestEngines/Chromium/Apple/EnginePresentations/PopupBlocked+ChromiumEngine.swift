#if CREST_CHROMIUM_HOST
    import Foundation

    extension PopupBlocked {
        @MainActor func present(on engine: ChromiumEngine) {
            guard let page = engine.presentedPage(pageID), let url = URL(string: pageURL) else { return }
            page.observer(BrowserPagePopupBlocked(pageURL: url))
        }
    }
#endif
