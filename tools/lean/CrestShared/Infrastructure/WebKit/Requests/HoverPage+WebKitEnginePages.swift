import Foundation

extension HoverPage {
    /// Only an agent the person allowed on the Mac asks this; iPhone and iPad
    /// offer no agents.
    @MainActor func answer(on pages: WebKitEnginePages) -> Answer {
        #if os(macOS)
            pages.agents.hover(self)
        #else
            false
        #endif
    }
}
