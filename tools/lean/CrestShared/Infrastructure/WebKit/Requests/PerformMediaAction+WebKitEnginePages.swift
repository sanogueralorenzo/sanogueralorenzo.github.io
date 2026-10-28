import Foundation

extension PerformMediaAction {
    /// Crest runs its WebKit pages' Media Session through its own bridge in the page.
    @MainActor func answer(on pages: WebKitEnginePages) -> Answer {
        false
    }
}
