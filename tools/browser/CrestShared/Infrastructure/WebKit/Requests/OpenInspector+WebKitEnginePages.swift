import Foundation

extension OpenInspector {
    @MainActor func answer(on pages: WebKitEnginePages) -> Answer {
        pages.openInspector(self)
    }
}
