@MainActor
protocol BrowserStoreInteractionObserving: AnyObject {
    func browserWillResetSession()
    func browserDidMoveTab(from source: BrowserTabRuntimeAssignment, to destination: BrowserSpaceRuntimeAssignment)
    func browserDidOpenBackgroundTab()
}

extension BrowserStoreInteractionObserving {
    /// The desktop shell presents confirmation; other observers keep their native presentation.
    func browserDidOpenBackgroundTab() {}
}
