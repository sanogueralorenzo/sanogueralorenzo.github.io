import Foundation

extension AnswerProfileNotification {
    @MainActor func answer(on pages: WebKitEnginePages) -> Answer {
        // Public embedded WebKit has no profile notification host.
        false
    }
}
