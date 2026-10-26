import Foundation

extension StopMediaCapture {
    @MainActor func answer(on pages: WebKitEnginePages) -> Answer {
        pages.stopCapture(self)
    }
}
