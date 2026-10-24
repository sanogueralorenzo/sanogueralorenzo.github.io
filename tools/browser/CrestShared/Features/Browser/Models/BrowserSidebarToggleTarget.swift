/// A window whose sidebar a toggle action moves. Each action calls the one
/// that takes the sidebar where it sends it.
@MainActor
protocol BrowserSidebarToggleTarget {
    func hideSidebar(reduceMotion: Bool)
    func dockSidebar(reduceMotion: Bool)
}
