#if CREST_CHROMIUM_HOST
    import Foundation

    extension ProfilePrepared {
        @MainActor func present(on engine: ChromiumEngine) {
            engine.preparations.removeValue(forKey: preparationID)?.resume(returning: ready)
        }
    }
#endif
