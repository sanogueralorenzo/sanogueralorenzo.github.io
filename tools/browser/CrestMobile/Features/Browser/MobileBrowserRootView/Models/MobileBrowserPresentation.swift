import CoreGraphics

/// How much room a window has. A compact window shows one thing at a time:
/// its sidebar is the full-screen tab viewer, and the page comes up over it.
/// A regular window keeps its sidebar beside the page. Each size carries what
/// differs between the two, so the models and views that lay a window out ask
/// it instead of asking which one it is.
struct MobileBrowserPresentation: Equatable, Sendable {
    // MARK: - Static Variables

    /// The narrowest window that keeps its sidebar beside the page.
    static let regularMinimumWidth: CGFloat = 600

    static let compact: MobileBrowserPresentation = MobileBrowserPresentation(
        name: "compact",
        presentsPageOverTabViewer: true,
        overlayTopPadding: MobileBrowserRootLayout.compactOverlayTopPadding,
        selectsTab: { $0.presentPageFromTabViewer() },
        placesSidebarForTabViewer: { $0.dockRegularSidebar() },
        preparesForLockedSpace: { $0.keepLockedSpaceOverCompactPage() },
        adaptsNavigation: { _ in },
        revealsSidebar: { $0.showTabViewer() },
        togglesSidebar: { $0.toggleCompactSidebar(reduceMotion: $1) },
        presentsHistory: { content in
            guard let space = content.browser.shownSpace, !content.spaceAccess.isLocked(space) else { return }
            content.historyAssignment = BrowserSpaceRuntimeAssignment(space: space)
        },
        beginsNewTab: { content in
            content.model.beginCompactNewTab()
            content.isAddressEditing = false
            content.addressFocusRequest &+= 1
        },
        opensLocation: { content in
            if content.navigation.defersPageActivation {
                content.model.activateSelectedTab()
            }
            Task { @MainActor in
                await Task.yield()
                content.isAddressEditing = true
                content.addressFocusRequest &+= 1
            }
        }
    )

    static let regular: MobileBrowserPresentation = MobileBrowserPresentation(
        name: "regular",
        presentsPageOverTabViewer: false,
        overlayTopPadding: MobileBrowserRootLayout.regularOverlayTopPadding,
        // A regular window shows the page beside its sidebar already.
        selectsTab: { _ in },
        placesSidebarForTabViewer: { _ in },
        preparesForLockedSpace: { $0.keepLockedSpaceBesidePage() },
        adaptsNavigation: { $0.leaveNarrowWidth() },
        revealsSidebar: { $0.showRegularSidebar() },
        togglesSidebar: { $0.toggleRegularSidebar(reduceMotion: $1) },
        presentsHistory: { content in
            content.model.revealSidebarForUtilityCommand(presentation: .regular)
            content.navigation.utilityPresentation.present(.history)
        },
        beginsNewTab: { content in
            // The Start Page searches in its own field; any other page opens
            // the overlay palette.
            if content.showsStartPage {
                content.focusStartPageCommandPalette()
            } else {
                content.commandPaletteMode = .newTab
            }
        },
        opensLocation: { content in
            content.showRegularSidebar()
            if content.showsStartPage {
                content.focusStartPageCommandPalette()
            } else {
                content.commandPaletteMode = .editLocation(content.address)
            }
        }
    )

    // MARK: - Variables

    let name: String

    /// Whether the window's sidebar is the full-screen tab viewer, with the
    /// page presented over it. A regular window instead keeps its sidebar
    /// beside the page, shows the overlay command palette and the window's
    /// atmosphere, and owns its sidebar's width and visibility.
    let presentsPageOverTabViewer: Bool

    /// How far below the top edge transient feedback floats.
    let overlayTopPadding: CGFloat

    private let selectsTab: @MainActor @Sendable (MobileBrowserNavigationState) -> Void
    private let placesSidebarForTabViewer: @MainActor @Sendable (MobileBrowserNavigationState) -> Void
    private let preparesForLockedSpace: @MainActor @Sendable (MobileBrowserNavigationState) -> Void
    private let adaptsNavigation: @MainActor @Sendable (MobileBrowserNavigationState) -> Void
    private let revealsSidebar: @MainActor @Sendable (MobileBrowserNavigationState) -> Void
    private let togglesSidebar: @MainActor @Sendable (MobileBrowserRootModel, Bool) -> Void
    private let presentsHistory: @MainActor @Sendable (MobileBrowserRootContent) -> Void
    private let beginsNewTab: @MainActor @Sendable (MobileBrowserRootContent) -> Void
    private let opensLocation: @MainActor @Sendable (MobileBrowserRootContent) -> Void

    /// How the window shows Settings.
    @MainActor
    var settingsStyle: MobileBrowserSettingsStyle {
        presentsPageOverTabViewer ? .sheet : .embedded
    }

    // MARK: - Initializers

    private init(
        name: String,
        presentsPageOverTabViewer: Bool,
        overlayTopPadding: CGFloat,
        selectsTab: @escaping @MainActor @Sendable (MobileBrowserNavigationState) -> Void,
        placesSidebarForTabViewer: @escaping @MainActor @Sendable (MobileBrowserNavigationState) -> Void,
        preparesForLockedSpace: @escaping @MainActor @Sendable (MobileBrowserNavigationState) -> Void,
        adaptsNavigation: @escaping @MainActor @Sendable (MobileBrowserNavigationState) -> Void,
        revealsSidebar: @escaping @MainActor @Sendable (MobileBrowserNavigationState) -> Void,
        togglesSidebar: @escaping @MainActor @Sendable (MobileBrowserRootModel, Bool) -> Void,
        presentsHistory: @escaping @MainActor @Sendable (MobileBrowserRootContent) -> Void,
        beginsNewTab: @escaping @MainActor @Sendable (MobileBrowserRootContent) -> Void,
        opensLocation: @escaping @MainActor @Sendable (MobileBrowserRootContent) -> Void
    ) {
        self.name = name
        self.presentsPageOverTabViewer = presentsPageOverTabViewer
        self.overlayTopPadding = overlayTopPadding
        self.selectsTab = selectsTab
        self.placesSidebarForTabViewer = placesSidebarForTabViewer
        self.preparesForLockedSpace = preparesForLockedSpace
        self.adaptsNavigation = adaptsNavigation
        self.revealsSidebar = revealsSidebar
        self.togglesSidebar = togglesSidebar
        self.presentsHistory = presentsHistory
        self.beginsNewTab = beginsNewTab
        self.opensLocation = opensLocation
    }

    // MARK: - Actions - Sizing

    /// The size a window of `availableWidth` points is.
    static func fitting(availableWidth: CGFloat) -> MobileBrowserPresentation {
        if availableWidth >= regularMinimumWidth {
            return .regular
        }
        return .compact
    }

    // MARK: - Actions - Page

    /// Whether the page drops its frame. A narrow window's docked page fills
    /// the screen, so it always does; otherwise the person's preference says.
    func usesBorderlessPageFrame(
        preferenceIsEnabled: Bool,
        sidebarPresentation: BrowserSidebarPresentation
    ) -> Bool {
        if presentsPageOverTabViewer, sidebarPresentation == .docked {
            return true
        }
        return preferenceIsEnabled
    }

    /// Only the phone's docked, full-screen page uses WebKit's obscured-inset
    /// contract. Floating sidebars and tablet cards retain their safe area.
    func usesEdgeToEdgeWebViewport(
        isPhone: Bool,
        sidebarPresentation: BrowserSidebarPresentation
    ) -> Bool {
        isPhone && presentsPageOverTabViewer && sidebarPresentation == .docked
    }

    // MARK: - Actions - Navigation

    /// Takes the window to the tab a row selection chose.
    @MainActor
    func selectTab(on navigation: MobileBrowserNavigationState) {
        selectsTab(navigation)
    }

    /// Settles the sidebar once the window shows its tab viewer.
    @MainActor
    func placeSidebarForTabViewer(on navigation: MobileBrowserNavigationState) {
        placesSidebarForTabViewer(navigation)
    }

    /// Keeps a locked Space's sidebar on screen in the placement the person
    /// is already in.
    @MainActor
    func prepareForLockedSpace(on navigation: MobileBrowserNavigationState) {
        preparesForLockedSpace(navigation)
    }

    /// Settles the window's navigation once it takes this size.
    @MainActor
    func adapt(_ navigation: MobileBrowserNavigationState) {
        adaptsNavigation(navigation)
    }

    // MARK: - Actions - Sidebar

    /// Whether selecting a tab puts the sidebar away: only a narrow window's
    /// floating sidebar, which would otherwise cover the page chosen in it.
    func dismissesSidebarOnTabSelection(
        sidebarPresentation: BrowserSidebarPresentation
    ) -> Bool {
        presentsPageOverTabViewer && sidebarPresentation == .floating
    }

    /// Brings the sidebar up for a list a command asked for.
    @MainActor
    func revealSidebar(on navigation: MobileBrowserNavigationState) {
        revealsSidebar(navigation)
    }

    @MainActor
    func toggleSidebar(on model: MobileBrowserRootModel, reduceMotion: Bool) {
        togglesSidebar(model, reduceMotion)
    }

    // MARK: - Actions - Commands

    @MainActor
    func presentHistory(in content: MobileBrowserRootContent) {
        presentsHistory(content)
    }

    @MainActor
    func beginNewTab(in content: MobileBrowserRootContent) {
        beginsNewTab(content)
    }

    @MainActor
    func openLocation(in content: MobileBrowserRootContent) {
        opensLocation(content)
    }

    // MARK: - Actions - Identity

    static func == (lhs: MobileBrowserPresentation, rhs: MobileBrowserPresentation) -> Bool {
        lhs.name == rhs.name
    }
}
