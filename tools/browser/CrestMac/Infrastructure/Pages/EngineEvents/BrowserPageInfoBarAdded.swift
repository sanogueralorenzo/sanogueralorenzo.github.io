/// The engine shows a bar over the page.
struct BrowserPageInfoBarAdded: BrowserPageEngineEvent {
    // MARK: - Variables

    let bar: BrowserEngineInfoBar

    // MARK: - Actions - Page

    func apply(to page: BrowserPage) {
        guard !page.engineInfoBars.contains(where: { $0.id == bar.id }) else { return }
        page.engineInfoBars.append(bar)
    }
}
