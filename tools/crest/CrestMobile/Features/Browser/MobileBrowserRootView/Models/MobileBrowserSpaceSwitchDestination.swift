/// Where a window goes once it leaves a locked Space, and what going there
/// does to the window.
@MainActor
struct MobileBrowserSpaceSwitchDestination: Equatable {
    // MARK: - Static Variables

    /// The full-screen tab viewer, with no page presented.
    static let tabViewer = MobileBrowserSpaceSwitchDestination(
        name: "tabViewer",
        settles: { model in
            model.navigation.prepareForSpaceSwitch()
            model.pages.deactivatePagePresentation()
            model.address = model.browser.shownTab?.url ?? ""
        }
    )

    /// The selected tab's page.
    static let selectedPage = MobileBrowserSpaceSwitchDestination(
        name: "selectedPage",
        settles: { $0.activateSelectedTab() }
    )

    // MARK: - Variables

    let name: String
    private let settles: @MainActor (MobileBrowserRootModel) -> Void

    // MARK: - Initializers

    private init(name: String, settles: @escaping @MainActor (MobileBrowserRootModel) -> Void) {
        self.name = name
        self.settles = settles
    }

    // MARK: - Actions - Locking

    /// Where a window in `presentation`, its sidebar at `sidebarPresentation`,
    /// goes after leaving a locked Space: a docked phone returns to its tab
    /// viewer, and anything else to the selected page.
    static func afterLeavingLockedSpace(
        in presentation: MobileBrowserPresentation,
        sidebarPresentation: BrowserSidebarPresentation
    ) -> MobileBrowserSpaceSwitchDestination {
        presentation.presentsPageOverTabViewer && sidebarPresentation == .docked
            ? .tabViewer
            : .selectedPage
    }

    /// Takes `model`'s window here.
    func settle(on model: MobileBrowserRootModel) {
        settles(model)
    }

    // MARK: - Actions - Identity

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.name == rhs.name
    }
}
