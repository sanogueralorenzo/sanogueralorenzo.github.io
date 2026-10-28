import Foundation

extension ObservePageActivity {
    /// Only an agent the person allowed on the Mac asks this; iPhone and iPad
    /// offer no agents.
    @MainActor func answer(on pages: WebKitEnginePages) -> Answer {
        #if os(macOS)
            pages.agents.observe(self)
        #else
            false
        #endif
    }
}
