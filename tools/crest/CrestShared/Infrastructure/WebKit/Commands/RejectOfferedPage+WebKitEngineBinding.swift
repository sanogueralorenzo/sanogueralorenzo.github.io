import Foundation

extension RejectOfferedPage {
    /// WebKit builds nothing for a popup the core refused: the page that
    /// asked for it gets no window.
    @MainActor func perform(on binding: WebKitEngineBinding) {}
}
