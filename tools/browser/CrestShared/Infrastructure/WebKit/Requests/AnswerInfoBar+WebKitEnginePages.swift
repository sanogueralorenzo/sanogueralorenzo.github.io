import Foundation

extension AnswerInfoBar {
    /// WebKit shows no bars of its own.
    @MainActor func answer(on pages: WebKitEnginePages) -> Answer {
        false
    }
}
