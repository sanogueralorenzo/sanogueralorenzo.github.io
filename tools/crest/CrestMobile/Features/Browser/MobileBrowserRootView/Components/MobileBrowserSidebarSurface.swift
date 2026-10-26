import SwiftUI

/// The compact shell's sidebar adapter: it resolves what this placement can do,
/// binds the sidebar's ports to the compact page store, and owns the sheets the
/// chrome asks for.
///
/// One shell puts the sidebar on screen three ways — filling the window as the
/// tab viewer, floating over a page, and docked beside one — and each way makes
/// its own choices about where the utility lists come up, whether the pager
/// paints its own ground, and whether the bottom inset is held open. Those
/// arrive as separate values rather than as one mode, because nothing under here
/// should be able to ask which of the three it is.
struct MobileBrowserSidebarSurface: View {
    let browser: BrowserStore
    let pages: MobileBrowserPageStore
    let spaceAccess: BrowserSpaceAccessController

    /// Where the archive, history, and downloads lists come up.
    let utilityPresentationStyle: MobileBrowserSidebarUtilityPresentationStyle

    /// Whether each Space's page paints the Space's own branded ground, which a
    /// sidebar filling the window needs and one over a page does not.
    let showsPageBackdrop: Bool

    /// Whether the bottom inset is held open even while its controls are gone,
    /// which is what keeps a matched tab destination at one resting position.
    let reservesBottomChromeInset: Bool

    /// Whether the selected Space's page stays on screen beside the sidebar.
    let presentsSelectedSpacePage: Bool

    /// Whether the sidebar toggle detaches the sidebar rather than hiding or
    /// docking it.
    let sidebarToggleUndocks: Bool

    /// Whether selecting a tab zooms its page in with the system's own
    /// navigation transition.
    let usesNativeNavigationTransition: Bool

    let compactChromeNamespace: Namespace.ID
    /// Whether the address field holds its identity for the command palette
    /// or has handed it to the open palette. Only a placement beside an
    /// overlay palette takes part.
    let commandPaletteHandoff: BrowserCommandPaletteHandoff
    let tabPromotionNamespace: Namespace.ID
    @Binding var address: String
    @Binding var isAddressEditing: Bool
    let activateAddress: (() -> Void)?
    let selectTab: (UUID) -> Void
    let presentSettings: () -> Void
    let submitAddress: () -> Void
    let openURL: (URL) -> Void
    let openNewTab: () -> Void
    let showsCompactAddressBar: Bool
    let showsBottomSpaceSwitcher: Bool
    let compactPageIsFullyPresented: Bool
    let compactTransitionEnded: (CGSize) -> Void
    let togglePrivateBrowsing: () -> Void
    let closePrivateBrowsing: () -> Void
    let toggleSidebar: () -> Void
    let showsSidebarToggle: Bool
    let sidebarIsPresented: Bool
    let sidebarIsDocked: Bool
    let utilityPresentation: BrowserUtilityPresentationState

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.mobileBrowserControlPlacement) private var controlPlacement
    @State private var showsPasswords = false
    @State private var presentedSpaceSheet: MobileBrowserSidebarSpaceSheet?

    var body: some View {
        MobileBrowserSidebarPresentation(configuration: presentation) {
            BrowserSidebar(
                browser: browser,
                pageAccess: pageAccess,
                spaceAccess: spaceAccess,
                capabilities: capabilities,
                utilityCoordinator: utilityCoordinator,
                utilityPresentation: utilityPresentation,
                chromeActions: chromeActions,
                presentsSelectedSpacePage: presentsSelectedSpacePage,
                spaceSelectionChanged: synchronizeAddress(for:)
            ) { context in
                MobileBrowserSidebarContent(
                    configuration: contentConfiguration(context)
                )
            }
        }
        .toolbarVisibility(controlPlacement.barVisibility, for: .navigationBar)
    }

    /// What this shell can do: a finger is the primary input, a trackpad may
    /// still be attached, the sections draw their drop feedback on the rows, and
    /// only the placement that pushes a page has a transition to zoom with.
    ///
    /// Nothing here grows out of a row through a matched-geometry pairing. The
    /// placement that pushes a page joins the row through the system's zoom
    /// instead; the two that keep the page on screen the whole time join nothing
    /// at all. Saying so is what keeps a partnerless anchor off the view the
    /// reorder lift is dragged from.
    private var capabilities: BrowserInteractionCapabilities {
        BrowserInteractionCapabilities(
            supportsHover: true,
            supportsTouch: true,
            reservesReorderSectionZones: true,
            usesNativeNavigationTransition: usesNativeNavigationTransition,
            pairsRowWithPromotedSurface: false
        )
    }

    private var pageAccess: BrowserSidebarPageAccess {
        BrowserSidebarPageAccess(pages: pages, browser: browser, spaceAccess: spaceAccess)
    }

    private var utilityCoordinator: BrowserSidebarUtilityCoordinator {
        BrowserSidebarUtilityCoordinator(
            browser: browser,
            pages: pages,
            spaceAccess: spaceAccess,
            selectTab: selectTab,
            openURL: openURL
        )
    }

    private var chromeActions: BrowserSidebarChromeActions {
        BrowserSidebarChromeActions(
            presentSpaceSettings: { _ in presentSettings() },
            presentHistory: presentHistory,
            presentPasswords: { showsPasswords = true },
            presentArchive: { presentSpaceSheet(.archive) },
            presentDownloads: { presentSpaceSheet(.downloads) }
        )
    }

    private var presentation: MobileBrowserSidebarPresentationConfiguration {
        MobileBrowserSidebarPresentationConfiguration(
            browser: browser,
            pages: pages,
            spaceAccess: spaceAccess,
            selectedColorScheme: selectedSidebarColorScheme,
            showsPasswords: $showsPasswords,
            presentedSpaceSheet: $presentedSpaceSheet,
            selectedSpaceAssignment: selectedSpaceAssignment,
            selectTab: selectTab,
            openURL: openURL
        )
    }

    private func contentConfiguration(
        _ context: BrowserSidebarContext
    ) -> MobileBrowserSidebarContentConfiguration {
        MobileBrowserSidebarContentConfiguration(
            context: context,
            pages: pages,
            compactChromeNamespace: compactChromeNamespace,
            commandPaletteHandoff: commandPaletteHandoff,
            tabPromotionNamespace: tabPromotionNamespace,
            address: $address,
            isAddressEditing: $isAddressEditing,
            spaceActionsConfiguration: spaceActionsConfiguration(context),
            utilityPresentationStyle: utilityPresentationStyle,
            showsPageBackdrop: showsPageBackdrop,
            reservesBottomChromeInset: reservesBottomChromeInset,
            sidebarToggleUndocks: sidebarToggleUndocks,
            activateAddress: activateAddress,
            selectTab: selectTab,
            submitAddress: submitAddress,
            openNewTab: openNewTab,
            showsCompactAddressBar: showsCompactAddressBar,
            showsBottomSpaceSwitcher: showsBottomSpaceSwitcher,
            compactPageIsFullyPresented: compactPageIsFullyPresented,
            compactTransitionEnded: compactTransitionEnded,
            closePrivateBrowsing: closePrivateBrowsing,
            toggleSidebar: toggleSidebar,
            showsSidebarToggle: showsSidebarToggle,
            sidebarIsPresented: sidebarIsPresented,
            sidebarIsDocked: sidebarIsDocked
        )
    }

    private func spaceActionsConfiguration(
        _ context: BrowserSidebarContext
    ) -> MobileSpaceActionsConfiguration {
        MobileSpaceActionsConfiguration(
            showSettings: presentSettings,
            showArchive: { context.chromeActions.presentArchive?() },
            showDownloads: { context.chromeActions.presentDownloads?() },
            commonListsAreExpanded: utilityPresentation.isSwitcherExpanded,
            toggleCommonLists: context.toggleUtilitySwitcher,
            recordCommonListsTriggerFrame:
                utilityPresentation.recordTriggerFrame,
            togglePrivateBrowsing: togglePrivateBrowsing
        )
    }

    /// The sidebar reads its foreground from the shown Space's own branding
    /// rather than from the system appearance, as every compact placement
    /// does, so they keep agreeing.
    private var selectedSidebarColorScheme: ColorScheme {
        guard let space = browser.shownSpace else { return colorScheme }
        return space.settings.look.colorScheme(over: colorScheme)
    }

    private var selectedSpaceAssignment: BrowserSpaceRuntimeAssignment? {
        browser.shownSpace.map(BrowserSpaceRuntimeAssignment.init(space:))
    }

    private func presentHistory() {
        utilityPresentationStyle.presentHistory(from: self)
    }

    /// Puts one of the Space's lists up as a sheet, and refuses unless the Space
    /// is still the selected, unlocked one the sheet would be about.
    func presentSpaceSheet(_ surface: BrowserUtilitySurface) {
        guard utilityPresentationStyle == .sheet,
            let assignment = selectedSpaceAssignment,
            browser.selectedUnlockedSpace(matching: assignment, accessController: spaceAccess) != nil
        else { return }
        presentedSpaceSheet = MobileBrowserSidebarSpaceSheet(
            surface: surface,
            assignment: assignment
        )
        if surface == .downloads {
            pages.downloadCenter.acknowledgeItems(for: assignment.profileID)
        }
    }

    /// Brings the address field back in step once the session has moved.
    ///
    /// This shell owns the field, so it is the one that has to answer for it: a
    /// locked or vanished Space empties it, a placement that shows the page next
    /// to the sidebar takes the new Space's URL, and editing always ends because
    /// whatever was being typed belonged to the Space that was left.
    private func synchronizeAddress(for space: SpaceModel?) {
        if space == nil {
            address = ""
        } else if presentsSelectedSpacePage {
            address = browser.shownTab?.url ?? ""
        }
        isAddressEditing = false
    }
}

#Preview("Mobile Browser Sidebar") {
    @Previewable @Namespace var compactChromeNamespace
    @Previewable @Namespace var tabPromotionNamespace
    @Previewable @State var address = ""
    @Previewable @State var isAddressEditing = false
    let fixture = MobileBrowserSidebarPreviewFixture()

    MobileBrowserSidebarSurface(
        browser: fixture.browser,
        pages: fixture.pages,
        spaceAccess: fixture.spaceAccess,
        utilityPresentationStyle: .inline,
        showsPageBackdrop: false,
        reservesBottomChromeInset: false,
        presentsSelectedSpacePage: true,
        sidebarToggleUndocks: false,
        usesNativeNavigationTransition: false,
        compactChromeNamespace: compactChromeNamespace,
        commandPaletteHandoff: .neither,
        tabPromotionNamespace: tabPromotionNamespace,
        address: $address,
        isAddressEditing: $isAddressEditing,
        activateAddress: {},
        selectTab: { _ in },
        presentSettings: {},
        submitAddress: {},
        openURL: { _ in },
        openNewTab: {},
        showsCompactAddressBar: false,
        showsBottomSpaceSwitcher: true,
        compactPageIsFullyPresented: false,
        compactTransitionEnded: { _ in },
        togglePrivateBrowsing: {},
        closePrivateBrowsing: {},
        toggleSidebar: {},
        showsSidebarToggle: true,
        sidebarIsPresented: true,
        sidebarIsDocked: true,
        utilityPresentation: BrowserUtilityPresentationState()
    )
}
