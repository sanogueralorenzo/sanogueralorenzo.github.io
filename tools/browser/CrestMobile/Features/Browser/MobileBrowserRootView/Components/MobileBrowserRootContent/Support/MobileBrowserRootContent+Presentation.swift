import SwiftUI
import UIKit

extension MobileBrowserRootContent {
    var browser: BrowserStore { model.browser }
    var pages: MobileBrowserPageStore { model.pages }
    var navigation: MobileBrowserNavigationState { model.navigation }
    var spaceAccess: BrowserSpaceAccessController { model.spaceAccess }
    var address: String { model.address }

    var presentation: MobileBrowserPresentation {
        MobileBrowserPresentation.fitting(
            availableWidth: availableRootSize.width
        )
    }

    var presentsSplitView: Bool {
        guard let space = browser.shownSpace, !spaceAccess.isLocked(space) else { return false }
        return model.presentedSplitMembers.count > 1
    }

    /// Whether the window shows the Start Page, or no tab at all.
    var showsStartPage: Bool {
        browser.shownTab.map { $0.surface == .startPage } ?? true
    }

    var usesBorderlessPageFrame: Bool {
        presentation.usesBorderlessPageFrame(
            preferenceIsEnabled: chromeAppearance.borderless,
            sidebarPresentation: navigation.regularSidebarPresentation
        )
    }

    var showsCompactPageToolbar: Bool {
        Self.showsCompactPageToolbar(
            sidebarPresentation: navigation.regularSidebarPresentation,
            presentsSplitView: presentsSplitView
        )
    }

    /// The compact toolbar shows under a docked sidebar's page, and under a
    /// presented split whatever the sidebar's placement.
    nonisolated static func showsCompactPageToolbar(
        sidebarPresentation: BrowserSidebarPresentation,
        presentsSplitView: Bool
    ) -> Bool {
        presentsSplitView || sidebarPresentation == .docked
    }

    /// Whether the window leaves the keyboard's room unused: a keyboard that
    /// floats over the window, one narrower than most of it, or one that
    /// covers nothing of the screen, as a software keyboard put away beside a
    /// hardware one does, or one left behind as the window turns or moves to
    /// the other display.
    var ignoresKeyboardSafeArea: Bool {
        let floatingKeyboardMaximumWidthRatio: CGFloat = 0.85
        guard !keyboardEndFrame.isNull, !keyboardEndFrame.isEmpty else { return true }
        if !keyboardScreenBounds.isNull, !keyboardEndFrame.intersects(keyboardScreenBounds) {
            return true
        }
        guard availableRootSize.width > 0 else { return false }
        return keyboardEndFrame.width
            < availableRootSize.width * floatingKeyboardMaximumWidthRatio
    }

    var compactPagePresentation: Binding<Bool> {
        Binding(
            get: {
                navigation.compactShowsPage
                    && !suspendsCompactPagePresentation
            },
            set: { isPresented in
                guard !suspendsCompactPagePresentation else { return }
                if isPresented {
                    navigation.selectTab()
                } else {
                    navigation.dismissPageToTabViewer()
                }
            }
        )
    }

    /// Whether the page covers a narrow window, so a sheet shows from the
    /// page rather than from the window: a sheet asked of the window while
    /// the page covers it never appears.
    var pageCoversWindow: Bool {
        presentation.presentsPageOverTabViewer && compactPagePresentation.wrappedValue
    }

    /// Whether Settings shows as a sheet from the page, or from the window.
    func settingsSheet(overPage: Bool) -> Binding<Bool> {
        Binding(
            get: { model.showsSettings && pageCoversWindow == overPage },
            set: { model.showsSettings = $0 }
        )
    }

    var settingsSheetContent: some View {
        MobileBrowserSettingsView(
            browser: browser, pages: pages, spaceAccess: spaceAccess, dataDeleter: dataDeleter,
            state: model.settings.state)
    }

    /// The Space whose History shows as a sheet from the page, or from the
    /// window.
    func historySheet(overPage: Bool) -> Binding<BrowserSpaceRuntimeAssignment?> {
        Binding(
            get: { pageCoversWindow == overPage ? historyAssignment : nil },
            set: { historyAssignment = $0 }
        )
    }

    func historySheetContent(_ assignment: BrowserSpaceRuntimeAssignment) -> some View {
        MobileHistoryView(browser: browser, assignment: assignment, spaceAccess: spaceAccess, openURL: openURL)
    }

    /// Asks about a risky download from the page, or from the window.
    func downloadRiskConfirmation(overPage: Bool) -> MobileDownloadRiskConfirmationModifier {
        MobileDownloadRiskConfirmationModifier(
            confirmation: pages.downloadRiskConfirmation,
            profileIDs: Set(browser.spaceModels.map(\.profileID)),
            asks: pageCoversWindow == overPage
        )
    }

    /// The expanded detail area. The container decides whether it adjoins a
    /// docked sidebar, while the page and split composition stay identical.
    func regularPageSurface(
        adjoinsSidebar: Bool,
        commands: BrowserCommandPaletteCommandRegistry
    ) -> MobileRegularPageSurface {
        MobileRegularPageSurface(
            model: model,
            adjoinsSidebar: adjoinsSidebar,
            usesBorderlessPageFrame:
                usesBorderlessPageFrame,
            address: model.addressBinding,
            isAddressEditing: $isAddressEditing,
            addressFocusRequest: addressFocusRequest,
            isCommandPalettePresented: commandPaletteMode != nil,
            commands: commands,
            compactToolbarIsHidden: navigation.compactToolbarIsHidden,
            submitAddress: submitAddress,
            beginNewTab: beginNewTab,
            showTabViewer: showTabViewer,
            hideCompactToolbar: navigation.hideCompactToolbar,
            showCompactToolbar: navigation.showCompactToolbar,
            showSwipedTab: showSwipedTab,
            compactTransitionEnded: finishCompactTransition
        )
    }

    var compactTransition: MobileCompactChromeTransition {
        navigation.compactShowsPage ? .revealTabViewer : .revealPage
    }

    var mobileBrowserCommandContext: MobileBrowserCommandContext {
        model.commandContext(
            transientBrowsing: transientBrowsing,
            layoutDirection: layoutDirection,
            usesPageToolbars: !presentation.usesEdgeToEdgeWebViewport(
                isPhone: UIDevice.current.userInterfaceIdiom == .phone,
                sidebarPresentation: navigation.regularSidebarPresentation
            ),
            togglePrivateBrowsing: togglePrivateBrowsing,
            openNewTab: beginNewTab,
            openLocation: openLocation,
            prepareForSelectionSynchronization: dismissAddressFocus,
            toggleSidebar: toggleSidebarFromCommand,
            presentHistory: presentHistoryFromCommand,
            presentArchive: presentArchiveFromCommand,
            presentDownloads: presentDownloadsFromCommand
        )
    }
}
