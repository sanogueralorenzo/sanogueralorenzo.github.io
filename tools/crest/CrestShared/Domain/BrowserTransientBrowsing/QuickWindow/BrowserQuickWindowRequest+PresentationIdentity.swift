extension BrowserQuickWindowRequest {
    func hasSamePresentationIdentity(
        as other: BrowserQuickWindowRequest
    ) -> Bool {
        id == other.id
            && url == other.url
            && assignment == other.assignment
            && targetWindowID == other.targetWindowID
            && sourcePresentation == other.sourcePresentation
            && openedPageID == other.openedPageID
    }
}
