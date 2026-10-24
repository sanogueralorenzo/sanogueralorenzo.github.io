#if CREST_CHROMIUM_HOST
    import Foundation

    extension ShareSourcesOffered {
        /// The page asks the person which tab to share, or to go on to the
        /// system's picker. A page nobody shows refuses the request, so it
        /// never waits for an answer that cannot come.
        @MainActor func present(on engine: ChromiumEngine) {
            guard let page = engine.presentedPage(pageID) else {
                engine.pages?.request(
                    ChooseShareSource(pageID: pageID, shareID: shareID, choice: .cancel, tabPageID: nil, audio: false))
                return
            }
            page.observer(BrowserPageShareSourcesOffered(offer: BrowserShareSourceOffer(self)))
        }
    }
#endif
