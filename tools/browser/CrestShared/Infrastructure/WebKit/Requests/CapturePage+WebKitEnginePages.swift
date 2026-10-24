import Foundation

extension CapturePage {
    @MainActor func answer(on pages: WebKitEnginePages) -> Answer {
        pages.capture(self)
    }
}
