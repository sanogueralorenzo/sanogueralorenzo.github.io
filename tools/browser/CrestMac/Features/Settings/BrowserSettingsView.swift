import AppKit
import SwiftUI

struct BrowserSettingsView: View {
    @Environment(\.scenePhase) private var scenePhase
    let browser: BrowserStore
    let pages: BrowserPagePool
    let cloudSync: BrowserCloudSyncController
    let spaceAccess: BrowserSpaceAccessController
    let dataDeleter: any BrowserSpaceDataDeleting
    let shortcuts: BrowserShortcutStore
    let spaceSettingsPresentation: BrowserSpaceSettingsPresentationState
    let usesLiveSidebar: Bool

    @Bindable var tabState: BrowserSettingsTabState
    let tabAssignment: BrowserTabRuntimeAssignment?

    init(
        browser: BrowserStore,
        pages: BrowserPagePool,
        cloudSync: BrowserCloudSyncController,
        spaceAccess: BrowserSpaceAccessController = BrowserSpaceAccessController(),
        dataDeleter: (any BrowserSpaceDataDeleting)? = nil,
        shortcuts: BrowserShortcutStore,
        spaceSettingsPresentation: BrowserSpaceSettingsPresentationState =
            BrowserSpaceSettingsPresentationState(),
        usesLiveSidebar: Bool = true,
        tabState: BrowserSettingsTabState = BrowserSettingsTabState(),
        tabAssignment: BrowserTabRuntimeAssignment? = nil
    ) {
        self.tabState = tabState
        self.tabAssignment = tabAssignment
        self.browser = browser
        self.pages = pages
        self.cloudSync = cloudSync
        self.spaceAccess = spaceAccess
        self.dataDeleter = dataDeleter ?? pages
        self.shortcuts = shortcuts
        self.spaceSettingsPresentation = spaceSettingsPresentation
        self.usesLiveSidebar = usesLiveSidebar
    }

    var body: some View {
        HStack(spacing: 0) {
            BrowserSettingsSidebar(
                tabState: tabState, browser: browser, spaceAccess: spaceAccess, dataDeleter: dataDeleter,
                openSpace: openSpaceAction, addSpace: addSpace
            )
            .frame(width: 224)
            Divider()

            // The page stays built while its Space is off screen, as a webpage
            // does, so switching to this Space doesn't rebuild the form.
            page
                .id(tabState.navigation.selection)
                .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea(.container, edges: .top)
        .background(BrowserSettingsCanvas.background)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.browserSettingsTabState, tabState)
        .environment(\.browserSettingsIsTab, true)
        .environment(\.browserSettingsUsesLiveSidebar, usesLiveSidebar)
        .environment(\.browserSettingsOpenSpace, openSpaceAction)
        .onChange(of: scenePhase) { previousPhase, phase in
            lockPrivateSettings(previousPhase, phase)
        }
        .onChange(of: spaceSettingsPresentation.revision, initial: true) {
            _, revision in
            if let tabAssignment,
                spaceSettingsPresentation.requestedAssignment
                    != BrowserSpaceRuntimeAssignment(
                        spaceID: tabAssignment.spaceID, profileID: tabAssignment.profileID)
            {
                return
            }
            tabState.applyExternalRoute(
                spaceSettingsPresentation.request,
                spaceID: spaceSettingsPresentation.requestedSpaceID(in: browser),
                searchText: spaceSettingsPresentation.searchText,
                revision: revision
            )
        }
        .onChange(of: browser.spaceModels.map(\.id)) { _, ids in
            if case .space(let id) = tabState.navigation.selection, !ids.contains(id) {
                tabState.navigation.selection = .destination(.general)
            }
        }
    }

    @ViewBuilder
    private var page: some View {
        switch tabState.navigation.selection {
        case .destination(let destination):
            BrowserSettingsDestinationPage(
                destination: destination,
                tabAssignment: tabAssignment,
                browser: browser,
                pages: pages,
                cloudSync: cloudSync,
                spaceAccess: spaceAccess,
                dataDeleter: dataDeleter,
                shortcuts: shortcuts,
                spaceSettingsPresentation: spaceSettingsPresentation,
                select: { tabState.navigation.selection = .destination($0) }
            )
        case .space(let id):
            if let space = browser.spaceModel(id) {
                BrowserSettingsSpacePage(
                    browser: browser, pages: pages, space: space, spaceAccess: spaceAccess,
                    dataDeleter: dataDeleter, tabState: tabState, openSpace: openSpaceAction
                )
            }
        }
    }

    // MARK: - Spaces

    private var openSpaceAction: BrowserSettingsOpenSpaceAction {
        BrowserSettingsOpenSpaceAction { id, tab, intent in
            openSpace(id, tab: tab ?? tabState.spaceTab, intent: intent)
        }
    }

    /// Shows a Space's page. Settings in a window follows the Space: the
    /// window switches to it and its own Settings tab opens on the page.
    private func openSpace(_ id: UUID, tab: BrowserSpaceSettingsTab, intent: BrowserSettingsSpaceIntent) {
        guard let space = browser.spaceModel(id) else { return }
        guard usesLiveSidebar, let tabAssignment, id != tabAssignment.spaceID else {
            tabState.showSpace(id, tab: tab, intent: intent)
            return
        }
        guard
            let selected = BrowserSettingsSpaceSelectionAction(browser: browser, spaceAccess: spaceAccess)
                .select(id, matching: tabAssignment)
        else {
            // A locked Space asks to be unlocked in the window first.
            if spaceAccess.isLocked(space) { browser.selectSpace(id) }
            return
        }
        spaceSettingsPresentation.present(
            BrowserSettingsSpaceRequest(tab: tab, intent: intent),
            assignment: BrowserSpaceRuntimeAssignment(spaceID: selected.spaceID, profileID: selected.profileID),
            searchText: tabState.navigation.searchText
        )
        pages.select()
    }

    /// Adds a Space and opens its Appearance page with its name ready to type.
    private func addSpace() {
        tabState.isArrangingSpaces = false
        browser.addSpace()
        guard let space = browser.spaceModel(browser.selectedSpaceID) else { return }
        guard usesLiveSidebar, tabAssignment != nil else {
            tabState.showSpace(space.id, tab: .appearance, intent: .newSpace)
            return
        }
        spaceSettingsPresentation.present(
            BrowserSettingsSpaceRequest(tab: .appearance, intent: .newSpace),
            assignment: BrowserSpaceRuntimeAssignment(space: space))
        browser.openSettings()
        pages.select()
    }

    private func lockPrivateSettings(
        _ previousPhase: ScenePhase,
        _ phase: ScenePhase
    ) {
        guard phase != previousPhase, !NSApp.isActive else { return }

        switch phase {
        case .active:
            break
        case .inactive:
            spaceAccess.lockAllForInactiveScene()
        case .background:
            spaceAccess.lockAll()
        @unknown default:
            spaceAccess.lockAll()
        }
    }
}

#Preview {
    let browser = BrowserStore.preview()
    BrowserSettingsView(
        browser: browser,
        pages: BrowserPagePool(browser: browser),
        cloudSync: BrowserCloudSyncController(core: browser.core, configuration: nil),
        shortcuts: BrowserShortcutStore()
    )
}
