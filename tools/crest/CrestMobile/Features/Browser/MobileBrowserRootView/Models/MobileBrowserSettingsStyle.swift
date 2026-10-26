import Foundation

// MARK: - Types

/// Where activating a tab leads: its page, or Settings.
enum BrowserTabActivationDestination {
    case page
    case settings
}

/// How a window shows Settings: as a tab embedded beside a regular window's
/// sidebar, or as a sheet over a compact one. Each style opens, presents and
/// adapts Settings its own way.
@MainActor
struct MobileBrowserSettingsStyle: Equatable {
    // MARK: - Static Variables

    static let embedded = MobileBrowserSettingsStyle(
        name: "embedded",
        showsSettingsAsSheet: false,
        opens: { settings, _ in settings.openEmbeddedSettings() },
        presents: { settings, tab, _ in
            settings.browser.selectTab(tab.id)
            settings.pages.select()
            settings.navigation.selectTab()
            return true
        },
        adapts: { settings in
            if settings.showsSheet {
                let sheetState = settings.state
                let source = settings.sheetAssignment
                settings.dismissSheet()
                guard let sheetAssignment = source,
                    settings.browser.selectedUnlockedSpace(
                        matching: sheetAssignment, accessController: settings.spaceAccess)
                        != nil
                else { return }
                settings.openEmbeddedSettings(adopting: sheetState)
            } else if let space = settings.browser.shownSpace, !settings.spaceAccess.isLocked(space),
                settings.browser.shownTab?.nativeTabContent == .settings
            {
                settings.pages.select()
            } else {
                settings.routeSelectedSettingsAction()
            }
        }
    )

    static let sheet = MobileBrowserSettingsStyle(
        name: "sheet",
        showsSettingsAsSheet: true,
        opens: { settings, space in
            let settingsTab = space.tabs.models.first { $0.nativeTabContent == .settings }
            if let tab = settingsTab {
                guard let retained = settings.retainedState(for: tab, in: space) else { return }
                settings.state = retained
            } else if settings.sheetAssignment != BrowserSpaceRuntimeAssignment(space: space) {
                settings.state = MobileBrowserSettingsState()
            }
            settings.presentSheet(in: space, tabID: settingsTab?.id)
        },
        presents: { settings, tab, space in
            guard let retained = settings.retainedState(for: tab, in: space) else { return false }
            settings.state = retained
            settings.presentSheet(in: space, tabID: tab.id)
            return true
        },
        adapts: { $0.routeSelectedSettingsAction() }
    )

    // MARK: - Variables

    let name: String

    /// Whether a Settings tab shows as a sheet rather than in the window.
    let showsSettingsAsSheet: Bool

    private let opens: @MainActor (MobileBrowserSettingsPresentation, SpaceModel) -> Void
    private let presents: @MainActor (MobileBrowserSettingsPresentation, TabStateModel, SpaceModel) -> Bool
    private let adapts: @MainActor (MobileBrowserSettingsPresentation) -> Void

    // MARK: - Initializers

    private init(
        name: String,
        showsSettingsAsSheet: Bool,
        opens: @escaping @MainActor (MobileBrowserSettingsPresentation, SpaceModel) -> Void,
        presents: @escaping @MainActor (MobileBrowserSettingsPresentation, TabStateModel, SpaceModel) -> Bool,
        adapts: @escaping @MainActor (MobileBrowserSettingsPresentation) -> Void
    ) {
        self.name = name
        self.showsSettingsAsSheet = showsSettingsAsSheet
        self.opens = opens
        self.presents = presents
        self.adapts = adapts
    }

    // MARK: - Actions - Settings

    /// Where activating a tab showing `content` leads.
    func destination(for content: BrowserNativeTabContent?) -> BrowserTabActivationDestination {
        showsSettingsAsSheet && content == .settings ? .settings : .page
    }

    /// Opens Settings for `space`.
    func open(in space: SpaceModel, on settings: MobileBrowserSettingsPresentation) {
        opens(settings, space)
    }

    /// Presents `tab`, a Settings tab of `space`. False when its state is gone.
    func present(_ tab: TabStateModel, in space: SpaceModel, on settings: MobileBrowserSettingsPresentation) -> Bool {
        presents(settings, tab, space)
    }

    /// Moves what Settings shows into this style, as the window changes size.
    func adapt(_ settings: MobileBrowserSettingsPresentation) {
        adapts(settings)
    }

    // MARK: - Actions - Identity

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.name == rhs.name
    }
}
