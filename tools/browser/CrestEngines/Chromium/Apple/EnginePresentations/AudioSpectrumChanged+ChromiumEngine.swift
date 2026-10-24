#if CREST_CHROMIUM_HOST
    import Foundation

    extension AudioSpectrumChanged {
        @MainActor func present(on engine: ChromiumEngine) {
            engine.presentedPage(pageID)?.audioSpectrum?.receive(bands)
        }
    }
#endif
