/// What a window's sidebar toggle does from each place the sidebar can be.
/// Each presentation calls the one for its place, so a window toggles its
/// sidebar with `presentation.toggle(on: handler)`.
@MainActor
protocol BrowserSidebarToggleHandler {
    func toggleDockedSidebar()
    func toggleFloatingSidebar()
    func toggleCollapsedSidebar()
}
