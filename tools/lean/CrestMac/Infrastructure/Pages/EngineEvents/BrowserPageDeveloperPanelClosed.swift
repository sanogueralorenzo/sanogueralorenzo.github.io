/// The inspector went away on its own: its close button, an undocked window
/// close, or the engine tearing it down.
struct BrowserPageDeveloperPanelClosed: BrowserPageEngineEvent {
    // MARK: - Actions - Page

    func apply(to page: BrowserPage) {
        // Without this the next Console command would try to close a panel
        // that is already gone instead of opening one.
        page.developerPanel = nil
    }
}
