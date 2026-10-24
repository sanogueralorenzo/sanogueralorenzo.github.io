import Foundation

extension RefreshPageIcon {
    /// Crest fetches its WebKit pages' icons itself.
    @MainActor func answer(on pages: WebKitEnginePages) -> Answer {
        false
    }
}
