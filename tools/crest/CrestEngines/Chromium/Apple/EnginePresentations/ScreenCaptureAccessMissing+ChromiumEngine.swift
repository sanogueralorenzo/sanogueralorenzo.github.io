#if CREST_CHROMIUM_HOST
    import Foundation

    extension ScreenCaptureAccessMissing {
        @MainActor func present(on engine: ChromiumEngine) {
            ChromiumComposition.showScreenRecordingNotice()
        }
    }
#endif
