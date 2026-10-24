#if CREST_CHROMIUM_HOST
    import Foundation

    extension InspectorLayoutChanged {
        @MainActor func present(on engine: ChromiumEngine) {
            engine.presentedPage(pageID)?.refreshDevTools()
        }
    }
#endif
