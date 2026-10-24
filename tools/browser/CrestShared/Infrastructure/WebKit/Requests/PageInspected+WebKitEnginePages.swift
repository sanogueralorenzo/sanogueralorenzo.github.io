import Foundation

extension PageInspected {
    @MainActor func answer(on pages: WebKitEnginePages) -> Answer {
        pages.isInspected(pageID)
    }
}
