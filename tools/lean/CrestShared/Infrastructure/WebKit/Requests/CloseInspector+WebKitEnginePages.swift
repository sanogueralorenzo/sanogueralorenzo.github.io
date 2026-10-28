import Foundation

extension CloseInspector {
    @MainActor func answer(on pages: WebKitEnginePages) -> Answer {
        pages.closeInspector(pageID)
    }
}
