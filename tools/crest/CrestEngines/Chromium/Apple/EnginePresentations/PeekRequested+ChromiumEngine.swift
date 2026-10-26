#if CREST_CHROMIUM_HOST
    import Foundation

    extension PeekRequested {
        @MainActor func present(on engine: ChromiumEngine) {
            guard let page = engine.presentedPage(pageID), let address = URL(string: url) else { return }
            page.observer(
                BrowserPagePeekRequested(
                    destination: address, decision: decision,
                    stagedLink: stagedLinkID.map {
                        BrowserEngineNavigation(
                            implementation: page.registration.implementationId, linkID: $0,
                            sourcePageID: pageID)
                    }))
        }
    }
#endif
