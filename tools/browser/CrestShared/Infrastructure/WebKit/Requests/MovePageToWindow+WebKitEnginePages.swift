import Foundation

extension MovePageToWindow {
    /// A web view travels with its page from window to window.
    @MainActor func answer(on pages: WebKitEnginePages) -> Answer {
        pages.page(pageID) != nil
    }
}
