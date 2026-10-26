import SwiftUI

extension MobileBrowserRootContent {
    func selectTab(_ id: UUID) {
        dismissAddressFocus()
        let dismissesFloatingPhoneSidebar =
            presentation.dismissesSidebarOnTabSelection(
                sidebarPresentation: navigation.regularSidebarPresentation
            )
        model.selectTab(id)
        if dismissesFloatingPhoneSidebar {
            hideRegularSidebar()
        }
    }

    func submitAddress() {
        guard model.submitAddress() else { return }
        isAddressEditing = false
    }

    func openURL(_ url: URL) {
        model.openURL(url)
    }

    func beginNewTab() {
        presentation.beginNewTab(in: self)
    }

    func openLocation() {
        presentation.openLocation(in: self)
    }

    func focusStartPageCommandPalette() {
        model.focusStartPageAddress()
        isAddressEditing = false
        addressFocusRequest &+= 1
    }

    func showTabViewer() {
        dismissAddressFocus()
        model.showTabViewer()
    }

    func finishCompactTransition(_ predictedEndTranslation: CGSize) {
        guard presentation.presentsPageOverTabViewer else { return }
        guard compactTransition.commits(predictedEndTranslation: predictedEndTranslation) else { return }
        isAddressEditing = false
        compactTransition.finish(in: self)
    }

    /// Brings the sidebar up from the compact chrome's upward swipe, in the
    /// placement this window already keeps it in.
    ///
    /// `MobileCompactSidebarRevealDestination` carries the reasoning. The short of it
    /// is that the full-screen viewer is the docked sidebar, so a docked window
    /// goes on landing there, while an undocked one — which only has this
    /// toolbar to swipe because a split is on show — floats the sidebar over the
    /// split instead of dropping the split to reach it.
    func revealSidebarFromCompactChrome() {
        MobileCompactSidebarRevealDestination.destination(
            sidebarPresentation: navigation.regularSidebarPresentation
        )
        .reveal(in: self)
    }

    /// Shows the tab the address bar's swipe landed on, which the core chose
    /// from the shown Space. Keyboard Space switching (⌥⌘←/→) goes through
    /// `MobileBrowserCommandController`, not through here, and the swipe never
    /// switches Spaces.
    func showSwipedTab(_ tabID: UUID) {
        model.showSwipedTab(tabID)
    }

    func toggleSidebarFromCommand() {
        if presentation.presentsPageOverTabViewer, navigation.compactShowsPage {
            dismissAddressFocus()
        }
        model.toggleSidebar(
            presentation: presentation,
            reduceMotion: reduceMotion
        )
    }

    func hideRegularSidebar() {
        model.hideRegularSidebar(reduceMotion: reduceMotion)
    }

    func showRegularSidebar() {
        model.showRegularSidebar(reduceMotion: reduceMotion)
    }

    func toggleRegularSidebar() {
        model.toggleSidebar(
            presentation: .regular,
            reduceMotion: reduceMotion
        )
    }

    func toggleCompactSidebar() {
        dismissAddressFocus()
        model.toggleSidebar(
            presentation: .compact,
            reduceMotion: reduceMotion
        )
    }

    func dismissAddressFocus() {
        isAddressEditing = false
        BrowserAddressFocusDismissal.dismiss()
    }
}
