import Foundation

extension GoToHistoryEntry {
    /// WebKit goes to the item the entry names. An entry the page no longer
    /// keeps goes nowhere, and the page reports its history again so the
    /// core lists what WebKit keeps.
    @MainActor func perform(on binding: WebKitEngineBinding) {
        guard let page = binding.page(pageID) else { return }
        let signposter = CorePage.historySignposter
        signposter.emitEvent("Go To History Entry")
        if !page.engine.goToHistoryEntry(entryID) { page.host?.historyMayHaveChanged() }
    }
}
