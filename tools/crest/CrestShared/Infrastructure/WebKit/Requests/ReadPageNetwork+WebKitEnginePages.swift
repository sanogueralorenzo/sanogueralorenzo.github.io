import Foundation

extension ReadPageNetwork {
    /// Only an agent the person allowed on the Mac asks this; iPhone and iPad
    /// offer no agents.
    @MainActor func answer(on pages: WebKitEnginePages) -> Answer {
        #if os(macOS)
            pages.agents.network(self)
        #else
            PageNetworkLog(requests: [], dropped: 0)
        #endif
    }
}
