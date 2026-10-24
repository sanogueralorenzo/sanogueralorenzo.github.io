@MainActor
protocol BrowserStoreInteractionObserving: AnyObject {
    func browserWillResetSession()
    func browserDidMoveTab(from source: BrowserTabRuntimeAssignment, to destination: BrowserSpaceRuntimeAssignment)
}
