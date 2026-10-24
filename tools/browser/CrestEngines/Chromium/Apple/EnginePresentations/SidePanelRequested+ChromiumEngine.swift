#if CREST_CHROMIUM_HOST
    import Foundation

    extension SidePanelRequested {
        @MainActor func present(on engine: ChromiumEngine) {
            ChromiumComposition.routeSidePanel(self)
        }
    }
#endif
