import Foundation

extension ReadPageConsole {
    /// Only an agent the person allowed on the Mac asks this; iPhone and iPad
    /// offer no agents.
    @MainActor func answer(on pages: WebKitEnginePages) -> Answer {
        #if os(macOS)
            pages.agents.console(self)
        #else
            PageConsoleLog(messages: [], dropped: 0)
        #endif
    }
}
