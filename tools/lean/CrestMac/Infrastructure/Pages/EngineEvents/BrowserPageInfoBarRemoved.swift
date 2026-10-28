/// The engine took a bar down; a nil `id` names none in particular.
struct BrowserPageInfoBarRemoved: BrowserPageEngineEvent {
    // MARK: - Variables

    let id: Int?

    // MARK: - Actions - Page

    func apply(to page: BrowserPage) {
        page.engineInfoBars.removeAll { $0.id == id }
        if let id { page.minimizedInfoBarIDs.remove(id) }
    }
}
