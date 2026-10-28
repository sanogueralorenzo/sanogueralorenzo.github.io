/// A regular-width window's sidebar toggle: a hidden sidebar floats over the
/// page, a floating one docks beside it, and a docked one hides.
struct MobileRegularSidebarToggle: BrowserSidebarToggleHandler {
    // MARK: - Variables

    let navigation: MobileBrowserNavigationState

    // MARK: - Actions - Toggle

    func toggleCollapsedSidebar() {
        navigation.showRegularSidebar()
    }

    func toggleFloatingSidebar() {
        navigation.dockRegularSidebar()
    }

    func toggleDockedSidebar() {
        navigation.hideRegularSidebar()
    }
}
