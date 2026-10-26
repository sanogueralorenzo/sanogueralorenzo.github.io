import Foundation

extension ShowBlockedPopups {
    /// WebKit keeps no blocked popups of its own.
    @MainActor func answer(on pages: WebKitEnginePages) -> Answer {
        false
    }
}
