/// A narrow window's sidebar toggle. It uses the same three sidebar states as
/// regular-width windows while adapting only what "docked" means on a narrow
/// phone. Without a floating sidebar it moves between the tab viewer and the
/// page.
struct MobileCompactSidebarToggle: BrowserSidebarToggleHandler {
    // MARK: - Variables

    let navigation: MobileBrowserNavigationState

    // MARK: - Actions - Toggle

    func toggleDockedSidebar() {
        if navigation.allowsCompactFloatingSidebar {
            navigation.showRegularSidebar()
        }
        navigation.presentCompactPage()
    }

    func toggleFloatingSidebar() {
        navigation.showTabViewer()
    }

    func toggleCollapsedSidebar() {
        if navigation.allowsCompactFloatingSidebar {
            navigation.showRegularSidebar()
        } else {
            navigation.showTabViewer()
        }
    }
}
