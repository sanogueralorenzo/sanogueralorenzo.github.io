import SwiftUI

struct MobileBrowserSettingsView: View {
    let browser: BrowserStore
    let pages: MobileBrowserPageStore
    let spaceAccess: BrowserSpaceAccessController
    let dataDeleter: any BrowserSpaceDataDeleting

    let isInTab: Bool
    @Bindable var state: MobileBrowserSettingsState
    var liveSpaceSelection: BrowserSettingsLiveSpaceSelection?

    init(
        browser: BrowserStore,
        pages: MobileBrowserPageStore,
        spaceAccess: BrowserSpaceAccessController = BrowserSpaceAccessController(),
        dataDeleter: (any BrowserSpaceDataDeleting)? = nil,
        state: MobileBrowserSettingsState = MobileBrowserSettingsState(),
        isInTab: Bool = false,
        liveSpaceSelection: BrowserSettingsLiveSpaceSelection? = nil
    ) {
        self.state = state
        self.isInTab = isInTab
        self.liveSpaceSelection = liveSpaceSelection
        self.browser = browser
        self.pages = pages
        self.spaceAccess = spaceAccess
        self.dataDeleter = dataDeleter ?? pages
    }

    var body: some View {
        MobileBrowserSettingsContent(
            browser: browser,
            pages: pages,
            spaceAccess: spaceAccess,
            dataDeleter: dataDeleter,
            selection: $state.selection,
            searchText: $state.searchText,
            path: $state.path
        )
        .onAppear {
            if isInTab { state.prepareForEmbeddedPresentation() }
        }
        .environment(\.browserSettingsIsTab, isInTab)
        .environment(\.browserSettingsSelectLiveSpace, liveSpaceSelection)
    }
}

#Preview("Mobile Settings") {
    let fixture = MobileBrowserPreviewFixture()
    MobileBrowserSettingsView(
        browser: fixture.browser,
        pages: fixture.pages,
        spaceAccess: fixture.spaceAccess
    )
    .environment(fixture.cloudSync)
    .environment(fixture.onboardingCoordinator)
    .environment(fixture.passkeyAccess)
}
