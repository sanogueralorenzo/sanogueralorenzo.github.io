#if CREST_CHROMIUM_HOST
    import Foundation

    extension InspectorClosed {
        @MainActor func present(on engine: ChromiumEngine) {
            engine.presentedPage(pageID)?.developerPanelDidClose()
        }
    }
#endif
