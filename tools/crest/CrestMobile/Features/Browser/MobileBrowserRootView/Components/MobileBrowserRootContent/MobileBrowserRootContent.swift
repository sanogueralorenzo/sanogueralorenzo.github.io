import SwiftUI
import UIKit

struct MobileBrowserRootContent: View, BrowserChromeAnimating {
    @Environment(BrowserSidebarInteractionState.self) private var sidebarInteraction

    let model: MobileBrowserRootModel
    let dataDeleter: any BrowserSpaceDataDeleting
    let transientBrowsing: BrowserTransientBrowsingCoordinator
    let suspendsCompactPagePresentation: Bool
    let togglePrivateBrowsing: () -> Void
    let closePrivateBrowsing: () -> Void

    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.accessibilityReduceTransparency) var reduceTransparency
    @Environment(\.layoutDirection) var layoutDirection
    @State private var spacePagerPresentation = SpacePagerPresentation()
    @State var isAddressEditing = false
    @State var addressFocusRequest = 0
    @State var commandPaletteMode: BrowserCommandPaletteMode?
    @State var historyAssignment: BrowserSpaceRuntimeAssignment?
    @State var isURLCopiedFeedbackVisible = false
    @State var visiblePageFeedback: MobilePageFeedback?
    @State var storedRegularSidebarWidth: Double
    @State var availableRootSize = CGSize.zero
    @State var keyboardEndFrame = CGRect.null
    /// The screen the keyboard last reported for, in its own coordinates.
    @State var keyboardScreenBounds = CGRect.null
    @AppStorage(
        MobileBrowserRootPreferences.allowsFloatingSidebarKey, store: BrowserChromeAppearancePreference.defaults)
    private var allowsFloatingSidebar = false
    @Namespace var compactChromeNamespace
    @Namespace var tabPromotionNamespace

    init(
        model: MobileBrowserRootModel,
        dataDeleter: any BrowserSpaceDataDeleting,
        transientBrowsing: BrowserTransientBrowsingCoordinator,
        suspendsCompactPagePresentation: Bool,
        togglePrivateBrowsing: @escaping () -> Void,
        closePrivateBrowsing: @escaping () -> Void
    ) {
        self.model = model
        self.dataDeleter = dataDeleter
        self.transientBrowsing = transientBrowsing
        self.suspendsCompactPagePresentation = suspendsCompactPagePresentation
        self.togglePrivateBrowsing = togglePrivateBrowsing
        self.closePrivateBrowsing = closePrivateBrowsing
        _storedRegularSidebarWidth = State(
            initialValue: Double(model.sidebarWidth)
        )
    }

    var body: some View {
        // One reading of the window's commands serves the scene's menu and
        // both Start Page paths.
        let commandContext = mobileBrowserCommandContext
        MobileBrowserRootSurface(
            presentation: presentation,
            browser: browser,
            pages: pages,
            navigation: navigation,
            transientBrowsing: transientBrowsing,
            spaceAccess: spaceAccess,
            preferredSidebarWidth: model.sidebarWidth,
            isCommandPalettePresented: commandPaletteMode != nil,
            isURLCopiedFeedbackVisible: isURLCopiedFeedbackVisible,
            pageFeedback: visiblePageFeedback,
            reduceMotion: reduceMotion,
            didPromoteTransientPage: model.activateSelectedTab,
            compact: MobileCompactBrowserSurface(
                compactShowsPage: navigation.compactShowsPage,
                isPagePresented: compactPagePresentation,
                usesDockedDetailPresentation:
                    navigation.regularSidebarIsDocked,
                sidebarPresentation: navigation.regularSidebarPresentation,
                preferredSidebarWidth: model.sidebarWidthBinding,
                space: browser.shownSpace,
                spaces: browser.availableSpaces,
                reduceTransparency: reduceTransparency,
                layoutDirection: layoutDirection,
                usesBorderlessFloatingPageFrame:
                    usesBorderlessPageFrame,
                isStartPage: showsStartPage,
                hasActivePage: model.selectedPage != nil,
                completedNavigationCount:
                    model.selectedPage?.completedNavigationCount ?? 0,
                hasSelectedSpace: browser.shownSpace != nil,
                selectedPage: model.selectedPage,
                showSidebar: showRegularSidebar,
                handlePageInteraction: navigation.handleRegularPageInteraction,
                commitSidebarWidth: commitRegularSidebarWidth,
                dockedSidebar: MobileBrowserSidebarSurface(
                    browser: browser,
                    pages: pages,
                    spaceAccess: spaceAccess,
                    utilityPresentationStyle: .sheet,
                    showsPageBackdrop: true,
                    reservesBottomChromeInset: true,
                    presentsSelectedSpacePage: false,
                    sidebarToggleUndocks: true,
                    usesNativeNavigationTransition: true,
                    compactChromeNamespace: compactChromeNamespace,
                    commandPaletteHandoff: .neither,
                    tabPromotionNamespace: tabPromotionNamespace,
                    address: model.addressBinding,
                    isAddressEditing: $isAddressEditing,
                    activateAddress: openLocation,
                    selectTab: selectTab,
                    presentSettings: model.openSettings,
                    submitAddress: submitAddress,
                    openURL: openURL,
                    openNewTab: beginNewTab,
                    showsCompactAddressBar:
                        MobileCompactTabViewerLayout.showsTopAddressBar,
                    showsBottomSpaceSwitcher:
                        navigation.compactTabViewerChromeIsVisible,
                    compactPageIsFullyPresented:
                        navigation.compactPageIsFullyPresented,
                    compactTransitionEnded: finishCompactTransition,
                    togglePrivateBrowsing: togglePrivateBrowsing,
                    closePrivateBrowsing: closePrivateBrowsing,
                    toggleSidebar: toggleCompactSidebar,
                    showsSidebarToggle: allowsFloatingSidebar,
                    sidebarIsPresented: true,
                    sidebarIsDocked: true,
                    utilityPresentation: navigation.utilityPresentation
                ),
                floatingSidebar: MobileBrowserSidebarSurface(
                    browser: browser,
                    pages: pages,
                    spaceAccess: spaceAccess,
                    utilityPresentationStyle: .inline,
                    showsPageBackdrop: false,
                    reservesBottomChromeInset: false,
                    presentsSelectedSpacePage: true,
                    sidebarToggleUndocks: false,
                    usesNativeNavigationTransition: false,
                    compactChromeNamespace: compactChromeNamespace,
                    commandPaletteHandoff: .neither,
                    tabPromotionNamespace: tabPromotionNamespace,
                    address: model.addressBinding,
                    isAddressEditing: $isAddressEditing,
                    activateAddress: nil,
                    selectTab: selectTab,
                    presentSettings: model.openSettings,
                    submitAddress: submitAddress,
                    openURL: openURL,
                    openNewTab: beginNewTab,
                    showsCompactAddressBar: false,
                    showsBottomSpaceSwitcher: true,
                    compactPageIsFullyPresented: false,
                    compactTransitionEnded: finishCompactTransition,
                    togglePrivateBrowsing: togglePrivateBrowsing,
                    closePrivateBrowsing: closePrivateBrowsing,
                    toggleSidebar: toggleCompactSidebar,
                    showsSidebarToggle: true,
                    sidebarIsPresented:
                        navigation.compactSidebarPresentation.showsSidebar,
                    sidebarIsDocked: false,
                    utilityPresentation: navigation.utilityPresentation
                )
                .modifier(
                    BrowserPlatformObservedTapModifier(claimsTaps: true) {
                        navigation.handleRegularSidebarInteraction()
                    }
                )
                // Never zero: this rides over the rows, and a drag that begins
                // on touch-down takes the press the reorder lift needs.
                .simultaneousGesture(
                    DragGesture(
                        minimumDistance: MobileBrowserChromeLayout
                            .transientSidebarKeepAliveDistance
                    ).onChanged { _ in
                        navigation.handleRegularSidebarInteraction()
                    }
                ),
                page: MobileCompactPageSurface(
                    selectedTab: browser.shownTab,
                    isURLCopiedFeedbackVisible: isURLCopiedFeedbackVisible,
                    pageFeedback: visiblePageFeedback,
                    reduceMotion: reduceMotion,
                    tabPromotionNamespace: tabPromotionNamespace,
                    completePagePresentation:
                        navigation.completePagePresentation,
                    backdrop: MobileCompactPageBackdrop(
                        isStartPage: showsStartPage,
                        hasSelectedPage: model.selectedPage != nil,
                        pageThemeColor: model.selectedPage?.themeColor,
                        underPageBackgroundColor:
                            model.selectedPage?.underPageColor,
                        space: browser.shownSpace
                    ),
                    detail: MobileBrowserDetailSurface(
                        browser: browser,
                        pages: pages,
                        spaceAccess: spaceAccess,
                        address: model.addressBinding,
                        isAddressEditing: $isAddressEditing,
                        addressFocusRequest: addressFocusRequest,
                        isCommandPalettePresented:
                            commandPaletteMode != nil,
                        commands: commandContext.paletteRegistry,
                        isCompact: true,
                        obscuresSystemSafeAreas:
                            presentation.usesEdgeToEdgeWebViewport(
                                isPhone: UIDevice.current.userInterfaceIdiom == .phone,
                                sidebarPresentation: navigation.regularSidebarPresentation),
                        showsCompactToolbar: showsCompactPageToolbar,
                        compactToolbarIsHidden:
                            navigation.compactToolbarIsHidden,
                        handleWebContentInteraction:
                            navigation.handleRegularPageInteraction,
                        submitAddress: submitAddress,
                        beginNewTab: beginNewTab,
                        showTabViewer: showTabViewer,
                        hideCompactToolbar:
                            navigation.hideCompactToolbar,
                        showCompactToolbar:
                            navigation.showCompactToolbar,
                        showSwipedTab: showSwipedTab,
                        compactTransitionEnded: finishCompactTransition,
                        transientBrowsing: transientBrowsing,
                        didPromoteTransientPage: model.activateSelectedTab,
                        showHistory: presentHistoryFromCommand
                    )
                )
                // The page covers the window while it shows, so Settings,
                // History and download prompts present from it; the floating
                // sidebar lives on it too.
                .sheet(isPresented: settingsSheet(overPage: true)) { settingsSheetContent }
                .sheet(item: historySheet(overPage: true)) { historySheetContent($0) }
                .modifier(downloadRiskConfirmation(overPage: true))
            ),
            regular: { layout in
                MobileRegularBrowserLayout(
                    layout: layout,
                    sidebarPresentation:
                        navigation.regularSidebarPresentation,
                    preferredSidebarWidth: model.sidebarWidthBinding,
                    reduceTransparency: reduceTransparency,
                    layoutDirection: layoutDirection,
                    space: browser.shownSpace,
                    spaces: browser.availableSpaces,
                    showSidebar: showRegularSidebar,
                    commitSidebarWidth: commitRegularSidebarWidth,
                    sidebar: MobileBrowserSidebarSurface(
                        browser: browser,
                        pages: pages,
                        spaceAccess: spaceAccess,
                        utilityPresentationStyle: .inline,
                        showsPageBackdrop: false,
                        reservesBottomChromeInset: false,
                        presentsSelectedSpacePage: true,
                        sidebarToggleUndocks: false,
                        usesNativeNavigationTransition: false,
                        compactChromeNamespace: compactChromeNamespace,
                        commandPaletteHandoff: commandPaletteHandoff,
                        tabPromotionNamespace: tabPromotionNamespace,
                        address: model.addressBinding,
                        isAddressEditing: $isAddressEditing,
                        activateAddress: openLocation,
                        selectTab: selectTab,
                        presentSettings: model.openSettings,
                        submitAddress: submitAddress,
                        openURL: openURL,
                        openNewTab: beginNewTab,
                        showsCompactAddressBar: false,
                        showsBottomSpaceSwitcher: true,
                        compactPageIsFullyPresented: false,
                        compactTransitionEnded: finishCompactTransition,
                        togglePrivateBrowsing: togglePrivateBrowsing,
                        closePrivateBrowsing: closePrivateBrowsing,
                        toggleSidebar: toggleRegularSidebar,
                        showsSidebarToggle: true,
                        sidebarIsPresented:
                            navigation.regularSidebarIsPresented,
                        sidebarIsDocked:
                            navigation.regularSidebarIsDocked,
                        utilityPresentation:
                            navigation.utilityPresentation
                    )
                    .environment(
                        \.browserSettingsUsesLiveSidebar,
                        navigation.regularSidebarIsDocked && layout.reservesSidebarWidth
                    )
                    .modifier(
                        BrowserPlatformObservedTapModifier(claimsTaps: true) {
                            navigation.handleRegularSidebarInteraction()
                        }
                    )
                    // Never zero: this rides over the rows, and a drag that
                    // begins on touch-down takes the press the reorder lift
                    // needs.
                    .simultaneousGesture(
                        DragGesture(
                            minimumDistance: MobileBrowserChromeLayout
                                .transientSidebarKeepAliveDistance
                        ).onChanged { _ in
                            navigation.handleRegularSidebarInteraction()
                        }
                    ),
                    detail: regularPageSurface(
                        adjoinsSidebar:
                            navigation.regularSidebarIsDocked
                            && layout.reservesSidebarWidth,
                        commands: commandContext.paletteRegistry
                    )
                    .overlay {
                        MobileTransientBrowsingOverlay(
                            browser: browser, pages: pages, coordinator: transientBrowsing,
                            spaceAccess: spaceAccess, didPromote: model.activateSelectedTab)
                    }
                    .clipped()
                    .environment(
                        \.browserSettingsUsesLiveSidebar,
                        navigation.regularSidebarIsDocked && layout.reservesSidebarWidth)
                )
                .onChange(of: layout.splitsPagesAtFold, initial: true) { _, splits in
                    navigation.adaptToFoldedSplit(splits)
                }
                .overlay {
                    MobileRegularUtilityFanLayer(
                        layout: layout,
                        layoutDirection: layoutDirection,
                        triggerFrameInGlobal: navigation.utilityPresentation
                            .triggerFrameInGlobal,
                        sidebarIsPresented:
                            navigation.regularSidebarIsPresented,
                        isExpanded: navigation.utilityPresentation
                            .isSwitcherExpanded,
                        selectedSurface: navigation.utilityPresentation.surface,
                        badgeColor: browser.shownSpace.flatMap {
                            $0.settings.look.colors.first?.color
                        } ?? .accentColor,
                        downloads: model.selectedUtilityDownloads,
                        newDownloadCount: model.newUtilityDownloads.count,
                        downloadCenter: pages.downloadCenter,
                        profileID: browser.shownSpace?.profileID,
                        spaceID: browser.shownSpace?.id,
                        select: navigation.utilityPresentation.present
                    )
                }
            },
            palette: { contentInsets in
                MobileBrowserCommandPaletteLayer(
                    mode: commandPaletteMode,
                    browser: browser,
                    space: browser.shownSpace,
                    selectedTabID: browser.shownTab?.id,
                    commands: mobileBrowserCommandContext.paletteRegistry,
                    isSourceAvailable: model.isPaletteSourceAvailable,
                    selectTab: model.selectPaletteTab,
                    openURL: { source, url, mode, opening in
                        model.openPaletteURL(url, mode: mode, from: source, opening: opening)
                    },
                    dismiss: dismissCommandPalette,
                    morphNamespace: compactChromeNamespace,
                    overlayContentInsets: contentInsets
                )
            }
        )
        .environment(\.spacePagerPresentation, spacePagerPresentation)
        .focusedSceneValue(
            \.mobileBrowserCommandContext,
            commandContext
        )
        .sheet(isPresented: settingsSheet(overPage: false)) { settingsSheetContent }
        .onChange(of: model.selectionSnapshot, initial: true) { _, _ in
            model.settings.reconcile()
            model.routeSelectedSettingsAction()
        }
        .onChange(of: suspendsCompactPagePresentation) { _, isSuspended in
            if isSuspended { model.settings.dismissSheet() }
        }
        .onChange(of: model.lockedSpaceIDs) {
            model.settings.reconcile()
        }
        .sheet(item: historySheet(overPage: false)) { historySheetContent($0) }
        .modifier(downloadRiskConfirmation(overPage: false))
        .onChange(of: pages.urlCopyFeedbackRevision) { _, revision in
            presentURLCopyFeedback(revision: revision)
        }
        .onChange(of: pages.pageFeedbackRevision) { _, revision in
            presentPageFeedback(revision: revision)
        }
        .modifier(
            MobileBrowserRootLifecycleModifier(
                model: model,
                presentation: presentation,
                openNewTab: beginNewTab,
                isAddressEditing: $isAddressEditing,
                storedSidebarWidth: $storedRegularSidebarWidth
            )
        )
        .onChange(of: allowsFloatingSidebar, initial: true) { _, allows in
            navigation.allowsCompactFloatingSidebar = allows
        }
        .onChange(
            of: isAddressEditing || sidebarInteraction.sidebarReorderState.isDragging,
            initial: true
        ) { _, keepsSidebarVisible in
            navigation.setTransientSidebarDismissalPaused(keepsSidebarVisible)
        }
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            availableRootSize = size
            guard size.width > 0 else { return }
            model.presentationChanged(to: MobileBrowserPresentation.fitting(availableWidth: size.width))
        }
        .ignoresSafeArea(
            .keyboard,
            edges: ignoresKeyboardSafeArea ? .bottom : []
        )
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIResponder.keyboardWillChangeFrameNotification
            )
        ) { notification in
            keyboardEndFrame =
                notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey]
                as? CGRect ?? .null
            keyboardScreenBounds = (notification.object as? UIScreen)?.bounds ?? .null
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIResponder.keyboardWillHideNotification
            )
        ) { _ in
            keyboardEndFrame = .null
        }
    }
}
