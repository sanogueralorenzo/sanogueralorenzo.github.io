import Foundation
import Observation

/// Routes settings through the measured layout while retaining its native-tab state.
@Observable @MainActor
final class MobileBrowserSettingsPresentation {
    let browser: BrowserStore
    let pages: MobileBrowserPageStore
    let navigation: MobileBrowserNavigationState
    let spaceAccess: BrowserSpaceAccessController
    private var style: MobileBrowserSettingsStyle?
    private(set) var sheetAssignment: BrowserSpaceRuntimeAssignment?
    private var sheetTabID: UUID?
    var state = MobileBrowserSettingsState()
    private(set) var showsSheet = false

    init(
        browser: BrowserStore, pages: MobileBrowserPageStore,
        navigation: MobileBrowserNavigationState, spaceAccess: BrowserSpaceAccessController
    ) {
        self.browser = browser
        self.pages = pages
        self.navigation = navigation
        self.spaceAccess = spaceAccess
    }

    func destination(for tab: TabStateModel) -> BrowserTabActivationDestination {
        (style ?? .embedded).destination(for: tab.nativeTabContent)
    }

    func adapt(to layout: MobileBrowserPresentation) {
        reconcile()
        style = layout.settingsStyle
        layout.settingsStyle.adapt(self)
    }

    func open() {
        guard let style, let space = browser.shownSpace, !spaceAccess.isLocked(space) else { return }
        style.open(in: space, on: self)
    }

    @discardableResult
    func present(matching assignment: BrowserTabRuntimeAssignment) -> Bool {
        guard let style,
            let space = browser.selectedUnlockedSpace(
                matching: BrowserSpaceRuntimeAssignment(spaceID: assignment.spaceID, profileID: assignment.profileID),
                accessController: spaceAccess),
            let tab = space.tabs.model(assignment.tabID), tab.nativeTabContent == .settings
        else { return false }
        return style.present(tab, in: space, on: self)
    }

    @discardableResult
    func routeSelectedSettingsAction() -> Bool {
        guard style?.showsSettingsAsSheet == true,
            let space = browser.shownSpace, !spaceAccess.isLocked(space),
            let tab = browser.shownTab, tab.nativeTabContent == .settings
        else { return false }
        guard let retained = retainedState(for: tab, in: space) else { return false }
        state = retained
        browser.dismissNativeTab(tab.id, matching: BrowserSpaceRuntimeAssignment(space: space))
        pages.select()
        presentSheet(in: space, tabID: tab.id)
        return true
    }

    @discardableResult
    func selectLiveSpace(_ id: UUID, matching source: BrowserTabRuntimeAssignment) -> Bool {
        guard style?.showsSettingsAsSheet == false,
            BrowserSettingsSpaceSelectionAction(browser: browser, spaceAccess: spaceAccess)
                .select(id, matching: source) != nil
        else { return false }
        synchronizeEmbeddedSettings()
        state.selection = .spaces
        return true
    }

    func reconcile() {
        guard showsSheet else { return }
        guard let sheetAssignment,
            let space = browser.selectedUnlockedSpace(matching: sheetAssignment, accessController: spaceAccess),
            sheetTabID == nil || sheetTabID.flatMap({ space.tabs.model($0) })?.nativeTabContent == .settings
        else {
            dismissSheet()
            return
        }
    }

    func dismissSheet() {
        showsSheet = false
        sheetAssignment = nil
        sheetTabID = nil
        state = MobileBrowserSettingsState()
    }

    func presentSheet(in space: SpaceModel, tabID: UUID?) {
        state.prepareForSheetPresentation()
        sheetAssignment = BrowserSpaceRuntimeAssignment(space: space)
        sheetTabID = tabID
        showsSheet = true
    }

    func openEmbeddedSettings(adopting sheetState: MobileBrowserSettingsState? = nil) {
        guard browser.openSettings() != nil else { return }
        synchronizeEmbeddedSettings(adopting: sheetState)
    }

    private func synchronizeEmbeddedSettings(adopting sheetState: MobileBrowserSettingsState? = nil) {
        guard let space = browser.shownSpace, let tab = browser.shownTab else { return }
        guard let retained = retainedState(for: tab, in: space) else { return }
        state = retained
        if let sheetState, sheetState !== state {
            state.selection = sheetState.selection
            state.searchText = sheetState.searchText
            state.path = sheetState.path
        }
        state.prepareForEmbeddedPresentation()
        pages.select()
        navigation.selectTab()
    }

    func retainedState(for tab: TabStateModel, in space: SpaceModel) -> MobileBrowserSettingsState? {
        pages.nativeTabs.load(tab: tab, space: space)
        let assignment = BrowserTabRuntimeAssignment(tabID: tab.id, spaceID: space.id, profileID: space.profileID)
        return pages.nativeTabs.runtime(matching: assignment, content: .settings)?
            .model(MobileBrowserSettingsState.self, make: MobileBrowserSettingsState.init)
    }
}
