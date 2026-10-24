import SwiftUI

struct MobileBrowserDetailView: View {
    let browser: BrowserStore
    let pages: MobileBrowserPageStore
    let spaceAccess: BrowserSpaceAccessController
    @Binding var address: String
    @Binding var isAddressEditing: Bool
    let addressFocusRequest: Int
    let isCommandPalettePresented: Bool
    /// The window's commands, which the Start Page's palette offers once what
    /// is typed matches one.
    var commands: BrowserCommandPaletteCommandRegistry?
    let isCompact: Bool
    let obscuresSystemSafeAreas: Bool
    let showsCompactToolbar: Bool
    let compactToolbarIsHidden: Bool
    let handleWebContentInteraction: () -> Void
    let submitAddress: () -> Void
    let beginNewTab: () -> Void
    let showTabViewer: () -> Void
    let hideCompactToolbar: () -> Void
    let showCompactToolbar: () -> Void
    /// Shows the tab the address bar's swipe landed on.
    let showSwipedTab: (UUID) -> Void
    let compactTransitionEnded: (CGSize) -> Void
    var transientBrowsing: BrowserTransientBrowsingCoordinator?
    var didPromoteTransientPage: () -> Void = {}
    /// Opens History from the compact toolbar's history menus; a detail without
    /// that toolbar never calls it.
    var showHistory: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.mobileBrowserControlPlacement) private var controlPlacement
    /// The page area's safe area, measured once here and handed as data to
    /// every page the area draws, the shown tab and the tabs the address
    /// bar's swipe slides in beside it, so each lays its page out alike.
    @State private var resolvedSafeAreaInsets = EdgeInsets()
    @State private var downloadsAssignment: BrowserSpaceRuntimeAssignment?
    /// The address bar's swipe through the shown Space's tabs, which moves
    /// the page area and the bar together.
    @State private var tabSwipe = MobileTabSwipe()

    var body: some View {
        let pageActions = MobileSelectedPageActionPort(
            browser: browser,
            pages: pages,
            spaceAccess: spaceAccess
        )
        let page = selectedSpaceIsLocked ? nil : pageActions?.activePage
        let pagePresentation = PagePresentation.of(browser.shownTab?.surface, page: page, restoresUnloaded: isCompact)
        let viewport = pageViewport
        let livePage = pagePresentation == .livePage ? page : nil
        MobileTabSwipeStage(swipe: tabSwipe, shownTabID: browser.shownTab?.id, shownLiveTabID: livePage?.tabID) {
            slot, isMoving in
            stagePage(
                slot, isMoving: isMoving, livePage: livePage, page: page, presentation: pagePresentation,
                viewport: viewport)
        }
        .onChange(of: swipeShownTab, initial: true) { _, shown in
            tabSwipe.rest(
                beside: shown == nil
                    ? SwipeNeighborTabs(previousTabID: nil, nextTabID: nil) : browser.swipeNeighbors)
        }
        .onChange(of: splitNeighborIDs, initial: true) { _, neighbors in
            // A split's cards either side are kept loaded, so a swipe slides
            // them in live.
            for tabID in neighbors { pages.prepareResidentPage(for: tabID) }
        }
        .overlay {
            if isCompact, let transientBrowsing {
                MobileTransientBrowsingOverlay(
                    browser: browser, pages: pages, coordinator: transientBrowsing,
                    spaceAccess: spaceAccess, didPromote: didPromoteTransientPage
                )
                .clipped()
                .padding(.bottom, viewport.bottomChromeHeight)
            }
        }
        .background(safeAreaProbe)
        .safeAreaInset(edge: .top, spacing: 0) {
            if let page {
                BrowserCredentialChrome(
                    presentation: BrowserCredentialChromePresentation.resolve(
                        saveCandidate: page.credentialSaveCandidate,
                        fillRequest: page.credentialFillRequest
                    ),
                    fillPort: credentialFillPort(for: page),
                    savePort: credentialSavePort(for: page),
                    browser: browser,
                    capabilities: capabilities
                )
            }
        }
        .overlay(alignment: .bottom) {
            if isCompact, showsCompactToolbar {
                if browser.shownTab.map({ $0.surface == .startPage }) ?? true {
                    if !controlPlacement.movesControlsToToolbar {
                        MobileCompactStartPageToolbar(showTabViewer: showTabViewer)
                            .safeAreaPadding(.bottom, 0)
                            .zIndex(1)
                    }
                } else if compactToolbarIsHidden {
                    MobileCompactDomainChip(
                        url: page?.live.documentURL,
                        showToolbar: showCompactToolbar
                    )
                    .safeAreaPadding(.bottom, 0)
                    .zIndex(1)
                } else {
                    MobileCompactPageToolbar(
                        browser: browser,
                        pageActions: pageActions,
                        downloadsAccess: compactDownloadsAccess,
                        address: $address,
                        isAddressEditing: $isAddressEditing,
                        submitAddress: submitAddress,
                        beginNewTab: beginNewTab,
                        showTabViewer: showTabViewer,
                        showHistory: showHistory,
                        hideToolbar: hideCompactToolbar,
                        tabSwipe: tabSwipe,
                        canSwipeTabs: swipeShownTab != nil,
                        swipeNeighbors: { browser.swipeNeighbors },
                        showSwipedTab: showSwipedTab,
                        compactTransitionEnded: compactTransitionEnded
                    )
                    .safeAreaPadding(.bottom, 0)
                    .zIndex(1)
                }
            }
        }
        .overlay(alignment: isCompact ? .bottom : .topTrailing) {
            if let page, page.isFindPresented {
                BrowserFindBar(
                    port: findPort(for: page),
                    capabilities: capabilities,
                    isPageActive: true
                )
                .frame(
                    maxWidth: isCompact
                        ? .infinity
                        : MobileBrowserChromeLayout.regularFindMaximumWidth
                )
                .padding(
                    .horizontal,
                    isCompact
                        ? MobileBrowserChromeLayout.compactFindHorizontalPadding
                        : MobileBrowserChromeLayout.regularFindHorizontalPadding
                )
                .padding(
                    .top,
                    isCompact ? 0 : MobileBrowserChromeLayout.regularFindTopPadding
                )
                .padding(
                    .bottom,
                    isCompact && showsCompactToolbar
                        ? compactBottomChromeHeight
                            + MobileBrowserChromeLayout.compactFindToolbarGap
                        : MobileBrowserChromeLayout.findFallbackBottomPadding
                )
                .zIndex(2)
                .transition(
                    reduceMotion
                        ? .opacity
                        : .move(edge: isCompact ? .bottom : .top)
                            .combined(with: .opacity)
                )
            }
        }
        .toolbar {
            if isCompact, showsCompactToolbar, controlPlacement.movesControlsToToolbar {
                compactToolbarItems(pageActions: pageActions)
            }
        }
        .animation(
            CrestMotion.toolbar.unlessReducingMotion(reduceMotion),
            value: page?.isFindPresented
        )
        .animation(
            CrestMotion.toolbar.unlessReducingMotion(reduceMotion),
            value: compactToolbarIsHidden
        )
        .sheet(item: $downloadsAssignment) { assignment in
            MobileDownloadsView(
                browser: browser,
                pages: pages,
                assignment: assignment,
                spaceAccess: spaceAccess
            )
        }
    }

    /// One page of the swipe stage. A live page draws one way in every place,
    /// so the page a swipe slides in keeps its host as it becomes the shown
    /// tab. A tab a swipe landed on keeps the placeholder it slid in with
    /// behind it until its page has drawn.
    private func stagePage(
        _ slot: MobileTabSwipeStageSlot, isMoving: Bool, livePage: MobileBrowserPage?,
        page: MobileBrowserPage?, presentation pagePresentation: PagePresentation, viewport: MobileBrowserPageViewport
    ) -> some View {
        Group {
            if let slotPage = slot.place == 0 ? livePage : swipeNeighborPage(slot.tabID) {
                MobileBrowserLivePageView(
                    page: slotPage,
                    viewport: viewport,
                    isActive: slot.place == 0 && pages.activePage === slotPage,
                    handleInteraction: slot.place == 0 ? handleWebContentInteraction : nil,
                    hidesFromAccessibility: slot.place != 0
                )
            } else if slot.place != 0 {
                if isMoving, let tabID = slot.tabID {
                    swipePlaceholder(of: tabID, viewport: viewport)
                }
            } else if selectedSpaceIsLocked {
                unloadedPageSurface
            } else {
                shownSurface(page: page, presentation: pagePresentation, viewport: viewport)
            }
        }
        .background {
            if slot.place == 0, let tabID = slot.tabID, tabID == tabSwipe.landedTabID, !selectedSpaceIsLocked,
                !hasDrawn(livePage)
            {
                swipePlaceholder(of: tabID, viewport: viewport)
            }
        }
    }

    /// What the shown tab shows when it shows no live page.
    @ViewBuilder
    private func shownSurface(
        page: MobileBrowserPage?, presentation pagePresentation: PagePresentation, viewport: MobileBrowserPageViewport
    ) -> some View {
        switch pagePresentation {
        case .nativeContent:
            if let tab = browser.shownTab, let space = browser.shownSpace {
                BrowserNativeTabHost(tab: tab, space: space, bottomChromeHeight: viewport.bottomChromeHeight)
            }
        case .unloaded:
            unloadedPageSurface
        case .noSelection, .startPage:
            if let space = browser.shownSpace {
                BrowserStartPage(
                    browser: browser,
                    space: space,
                    isPrivateBrowsing: browser.isPrivateBrowsing,
                    selectedTabID: browser.shownTab?.id,
                    isSourceAvailable: isPaletteSourceAvailable,
                    selectTab: selectStartPageTab,
                    openURL: openStartPageURL,
                    isCommandPaletteObscured: isCommandPalettePresented,
                    layout: isCompact ? .mobileCompactPage : .mobileRegularPage,
                    focusRequest: addressFocusRequest,
                    headerColorScheme: startPageHeaderColorScheme,
                    emptySelectionActions: emptySelectionPaletteActions,
                    commands: commands
                )
                .onChange(of: isCompact, initial: true) { _, compact in
                    if compact { address = "" }
                }
            } else {
                unloadedPageSurface
            }
        case .navigationFailure:
            if let page, let failure = page.live.failure {
                BrowserNavigationFailureView(
                    failure: failure,
                    branding: shownBranding,
                    layout: isCompact ? .compact : .regular,
                    canGoBack: page.canReturnFromNavigationFailure,
                    canProceed: page.canProceedAfterCertificateFailure,
                    retry: page.retryAfterNavigationFailure,
                    goBack: page.returnFromNavigationFailure,
                    proceed: page.proceedAfterCertificateFailure
                )
            } else {
                unloadedPageSurface
            }
        case .automaticRestore:
            unloadedPageSurface
                .onAppear {
                    restoreSelectedTab()
                }
        default:
            unloadedPageSurface
        }
    }

    /// What the page area's safe area is, measured clear of the keyboard.
    ///
    /// The probe ignores the keyboard region deliberately. SwiftUI spells
    /// keyboard avoidance as a safe area, so a probe that read it would report
    /// the keyboard's height as page chrome, and `MobileBrowserWebHostView`
    /// would inset the page by it a second time — on top of the shortening
    /// SwiftUI has already done — leaving the page laid out in a fraction of
    /// the web view with a dead band beneath it. What the page owes the
    /// keyboard is already paid by the layout; what it owes the window is what
    /// this measures.
    private var safeAreaProbe: some View {
        Color.clear
            .onGeometryChange(for: EdgeInsets.self) { proxy in
                proxy.safeAreaInsets
            } action: { insets in
                resolvedSafeAreaInsets = insets
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .accessibilityHidden(true)
    }

    private var compactDownloadsAccess: MobileDownloadsMenuAccess? {
        guard isCompact, let space = browser.shownSpace, !spaceAccess.isLocked(space) else { return nil }
        let items = pages.downloadCenter.items(for: space.profileID)
        return MobileDownloadsMenuAccess(
            newItemCount: pages.downloadCenter
                .unacknowledgedItems(for: space.profileID).count,
            activeProgress: items.notificationProgress,
            open: presentCompactDownloads
        )
    }

    private func presentCompactDownloads() {
        guard let space = browser.shownSpace, !spaceAccess.isLocked(space) else { return }
        let assignment = BrowserSpaceRuntimeAssignment(space: space)
        _ = pages.downloadCenter.acknowledgeItems(for: space.profileID)
        downloadsAssignment = assignment
    }

    /// The four questions the find bar asks, bound to the page it is over.
    private func findPort(for page: MobileBrowserPage) -> BrowserFindPort {
        BrowserFindPort(
            find: { query, direction in
                page.find(query, direction: direction)
            },
            query: { page.findQuery },
            matchState: { page.findMatchState },
            focusRequest: { page.findFocusRequest },
            dismiss: page.dismissFind
        )
    }

    /// The four things a credential fill prompt asks, bound to the page it is
    /// over.
    private func credentialFillPort(
        for page: MobileBrowserPage
    ) -> BrowserCredentialFillPort {
        BrowserCredentialFillPort(
            spaceID: page.spaceID,
            contentScale: page.pageZoom,
            siteIconData: page.faviconData,
            fill: { credential, requestID in
                try await page.fillCredential(credential, for: requestID)
            },
            fillGeneratedPassword: { password, requestID in
                try await page.fillGeneratedPassword(password, for: requestID)
            },
            dismiss: page.dismissCredentialFillRequest
        )
    }

    /// What the save prompt asks of the page it is over. This shell can hand a
    /// saved password on to the system's Passwords app, anchored on the window
    /// the page is living in at the moment the offer is made.
    private func credentialSavePort(
        for page: MobileBrowserPage
    ) -> BrowserCredentialSavePort {
        BrowserCredentialSavePort(
            spaceID: page.spaceID,
            presentedCandidateID: { page.credentialSaveCandidate?.id },
            dismiss: page.dismissCredentialSaveCandidate,
            offerToSystemPasswords: { candidate, title in
                try await BrowserSystemPasswordWriteThroughSystem.offer(
                    candidate: candidate,
                    title: title,
                    anchor: page.webView.window,
                    availability: browser.systemPasswordWriteThroughAvailability
                )
            }
        )
    }

    /// The compact page's controls where they move to the side toolbar:
    /// history at the top, the way back to the tabs at the bottom, and the
    /// address left over the page.
    @ToolbarContentBuilder
    private func compactToolbarItems(
        pageActions: MobileSelectedPageActionPort?
    ) -> some ToolbarContent {
        let port = BrowserSidebarNavigationPort(pageActions: pageActions, showHistory: showHistory)
        ToolbarItemGroup(placement: .topBarTrailing) {
            MobileHistoryToolbarControl(direction: .back, port: port)
            if port.canGoForward() {
                MobileHistoryToolbarControl(direction: .forward, port: port)
            }
        }
        ToolbarItemGroup(placement: .bottomBar) {
            Button("Tabs", systemImage: "square.on.square", action: showTabViewer)
                .accessibilityIdentifier("tab-viewer-button")
        }
    }

    /// What this shell can do, as far as the find bar and the credential
    /// prompts are concerned: they are aimed at with a finger, whichever
    /// placement they are drawn in.
    private var capabilities: BrowserInteractionCapabilities {
        BrowserInteractionCapabilities(supportsTouch: true)
    }

    /// The one viewport both paths render with.
    ///
    /// The selected tab on its own and every card of its group are handed this
    /// same value, which is what makes a grouped tab render exactly like the
    /// plain tab it is.
    private var pageViewport: MobileBrowserPageViewport {
        let safeAreaInsets = MobileBrowserPageViewport.systemSafeAreaInsets(
            resolvedSafeAreaInsets,
            layoutDirection: layoutDirection
        )
        return MobileBrowserPageViewport(
            obscuresSystemSafeAreas: obscuresSystemSafeAreas,
            systemSafeAreaInsets: safeAreaInsets,
            bottomChromeHeight: isCompact && showsCompactToolbar
                ? compactBottomChromeHeight
                : 0
        )
    }

    /// The cards beside the shown one in its split, on a phone, where a split
    /// shows one card at a time and the address bar's swipe slides the next
    /// one in. None in a locked Space, whose pages are put away.
    private var splitNeighborIDs: [UUID] {
        guard isCompact, let space = browser.shownSpace, !spaceAccess.isLocked(space),
            let shown = browser.shownTab?.id
        else { return [] }
        let members = browser.cards(in: space).map(\.id)
        guard let index = members.firstIndex(of: shown) else { return [] }
        return [index - 1, index + 1].filter(members.indices.contains).map { members[$0] }
    }

    /// The tab the address bar's swipe moves from, on a phone with the bar
    /// on show; nil where there is no swipe to make ready for.
    private var swipeShownTab: UUID? {
        guard isCompact, showsCompactToolbar, !selectedSpaceIsLocked else { return nil }
        return browser.shownTab?.id
    }

    /// The page a neighbour of the shown tab keeps in memory, drawn, for the
    /// address bar's swipe to slide in.
    private func swipeNeighborPage(_ tabID: UUID?) -> MobileBrowserPage? {
        guard let tabID, let page = pages.swipePreviewPage(for: tabID), hasDrawn(page) else { return nil }
        return page
    }

    /// Whether `page` has drawn content of its own, so nothing need stand in
    /// for it.
    private func hasDrawn(_ page: MobileBrowserPage?) -> Bool {
        page.map {
            BrowserPageSurfacePresentation.revealsWebContent(committedNavigationCount: $0.committedNavigationCount)
        } ?? false
    }

    /// What a neighbour with no page in memory shows as the swipe slides it in.
    @ViewBuilder
    private func swipePlaceholder(of tabID: UUID, viewport: MobileBrowserPageViewport) -> some View {
        if let space = browser.shownSpace, let tab = space.tabs.model(tabID) {
            MobileTabSwipePlaceholder(
                tab: tab,
                space: space,
                favicons: browser.core.state.favicons,
                bottomChromeHeight: viewport.bottomChromeHeight
            )
        }
    }

    /// The look of the Space this window shows, or nil for none.
    private var shownBranding: SpaceBranding? {
        browser.shownSpace.map(\.settings.look)
    }

    /// The appearance the start page's header reads its text tone from.
    ///
    /// Touch draws that header over the Space's branding, so the text follows
    /// the branding rather than the system appearance. Without a Space there is
    /// no brand to follow and the header inherits the environment's appearance.
    private var startPageHeaderColorScheme: ColorScheme? {
        guard let branding = shownBranding else { return nil }
        return branding.colorScheme(over: colorScheme)
    }

    private var unloadedPageSurface: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityHidden(true)
    }

    private var compactBottomChromeHeight: CGFloat {
        compactToolbarIsHidden
            ? MobileBrowserPageViewport.compactDomainChipHeight
            : MobileBrowserPageViewport.compactToolbarHeight
    }

    private var selectedSpaceIsLocked: Bool {
        browser.shownSpace.map(spaceAccess.isLocked) ?? false
    }

    private func restoreSelectedTab() {
        // The floating detail remains mounted behind the sidebar's lock view.
        // Relocking deactivates its page; that must never trigger auto-restore.
        guard let space = browser.shownSpace, !spaceAccess.isLocked(space) else { return }
        pages.select()
    }

    private var emptySelectionPaletteActions: BrowserEmptySelectionPaletteActions? {
        guard let space = browser.shownSpace, browser.shownTab == nil else { return nil }
        return BrowserEmptySelectionPaletteActions(
            source: BrowserSpaceRuntimeAssignment(space: space),
            browser: browser,
            accessController: spaceAccess,
            didSelectTab: {
                pages.select()
                address = browser.shownTab?.url ?? ""
            }
        )
    }

    private func openStartPageURL(
        _ source: BrowserTabRuntimeAssignment,
        _ url: URL
    ) -> Bool {
        guard isPaletteSourceAvailable(source) else { return false }
        withAnimation(
            CrestMotion.contentNavigation.unlessReducingMotion(reduceMotion)
        ) {
            browser.navigateSelectedTab(to: url.absoluteString)
            pages.selectAndNavigate(to: url.absoluteString)
        }
        return true
    }

    private func selectStartPageTab(
        _ source: BrowserTabRuntimeAssignment,
        _ target: BrowserTabRuntimeAssignment
    ) -> Bool {
        guard
            let destination = browser.paletteTarget(target, from: source, accessController: spaceAccess)
        else { return false }
        browser.selectSpace(destination.space.id)
        browser.selectTab(destination.tab.id)
        pages.select()
        return true
    }

    private func isPaletteSourceAvailable(
        _ source: BrowserTabRuntimeAssignment
    ) -> Bool {
        browser.isPaletteSourceAvailable(source, accessController: spaceAccess)
    }
}
