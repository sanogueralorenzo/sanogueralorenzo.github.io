import Foundation

extension CheckBeforeUnload {
    /// Asks the page's beforeunload handlers whether it may close, where
    /// WebKit runs them for an embedder close; any other page may go.
    @MainActor func perform(on binding: WebKitEngineBinding) {
        #if os(macOS)
            if let page = binding.page(pageID) {
                page.engine.prepareToClose { [weak binding] proceeds in
                    binding?.report(BeforeUnloadAnswered(pageID: pageID, proceeds: proceeds))
                }
                return
            }
        #endif
        binding.report(BeforeUnloadAnswered(pageID: pageID, proceeds: true))
    }
}
