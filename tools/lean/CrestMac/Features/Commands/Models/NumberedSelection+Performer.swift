extension NumberedSelection {
    /// Shows the stop or Space the selection leads to on `performer`.
    @MainActor
    func select(on performer: some BrowserNumberedSelectionPerformer) {
        switch target.kind {
        case .tab: performer.selectTab(tabID, in: spaceID)
        case .space: performer.selectSpace(spaceID)
        }
    }
}
