import Foundation

extension FindInPage {
    @MainActor func answer(on pages: WebKitEnginePages) -> Answer {
        pages.find(self)
    }
}
