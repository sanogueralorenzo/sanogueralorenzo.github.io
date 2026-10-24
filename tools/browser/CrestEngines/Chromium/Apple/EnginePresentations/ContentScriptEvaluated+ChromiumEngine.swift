#if CREST_CHROMIUM_HOST
    import Foundation

    extension ContentScriptEvaluated {
        @MainActor func present(on engine: ChromiumEngine) {
            engine.presentedPage(pageID)?.evaluations.removeValue(forKey: evaluationID)?.resume(returning: json)
        }
    }
#endif
