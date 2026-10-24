#if CREST_CHROMIUM_HOST
    import Foundation

    extension ExtensionsChanged {
        @MainActor func present(on engine: ChromiumEngine) {
            ChromiumComposition.extensions.refresh()
        }
    }
#endif
