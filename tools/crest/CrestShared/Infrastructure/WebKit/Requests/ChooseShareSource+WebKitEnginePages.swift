import Foundation

extension ChooseShareSource {
    /// WebKit shares the screen through its own prompt and offers no tabs.
    @MainActor func answer(on pages: WebKitEnginePages) -> Answer {
        false
    }
}
