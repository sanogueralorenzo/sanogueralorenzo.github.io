import Foundation

extension StopTabSharing {
    /// WebKit shares no tabs.
    @MainActor func answer(on pages: WebKitEnginePages) -> Answer {
        false
    }
}
