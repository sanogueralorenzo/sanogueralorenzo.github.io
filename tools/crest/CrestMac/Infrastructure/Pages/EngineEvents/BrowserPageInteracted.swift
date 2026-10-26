/// The person used the page.
struct BrowserPageInteracted: BrowserPageEngineEvent {
    // MARK: - Actions - Page

    func apply(to page: BrowserPage) {
        if page.awaitsInputSincePresented {
            page.awaitsInputSincePresented = false
            DiagnosticLog.pages.notice("Page \(page.corePage.id) takes the person's input")
        }
        page.userActivityHandler?()
    }
}
