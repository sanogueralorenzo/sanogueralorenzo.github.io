import Foundation

@MainActor
struct MobileBrowserPreviewFixture {
    let browser: BrowserStore
    let pages: MobileBrowserPageStore
    let cloudSync: BrowserCloudSyncController
    let passkeyAccess: BrowserPasskeyAccessController
    let windowState: BrowserWindowStateStore
    let space: SpaceModel
    let alternateSpace: SpaceModel

    init() {
        let space = SpaceState.Seed(
            id: UUID(
                uuid: (
                    0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x40, 0x00,
                    0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01
                )
            ),
            profileID: UUID(
                uuid: (
                    0x20, 0x00, 0x00, 0x00, 0x00, 0x00, 0x40, 0x00,
                    0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01
                )
            ),
            name: "Work",

            tabs: []
        )
        let alternateSpace = SpaceState.Seed(
            id: UUID(
                uuid: (
                    0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x40, 0x00,
                    0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02
                )
            ),
            profileID: UUID(
                uuid: (
                    0x20, 0x00, 0x00, 0x00, 0x00, 0x00, 0x40, 0x00,
                    0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02
                )
            ),
            name: "Personal",

            tabs: []
        )
        let browser = BrowserStore(
            seed: SessionState.Seed(spaces: [space, alternateSpace]), browsingMode: .privateBrowsing)
        guard let workSpace = browser.spaceModel(space.id), let personalSpace = browser.spaceModel(alternateSpace.id)
        else { preconditionFailure("The preview store must open both preview Spaces.") }
        browser.core.engines.register(WebKitEngineBinding(keepsProfilesInMemory: true))
        let pages = MobileBrowserPageStore(
            browser: browser,
            browsingMode: .privateBrowsing,
            usesEphemeralWebsiteDataStores: true,
            permissionCenter: BrowserSitePermissionCenter()
        )

        self.space = workSpace
        self.alternateSpace = personalSpace
        self.browser = browser
        self.pages = pages
        windowState = BrowserWindowStateStore(
            id: UUID(
                uuid: (
                    0x30, 0x00, 0x00, 0x00, 0x00, 0x00, 0x40, 0x00,
                    0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01
                )
            ),
            browser: browser,
            layouts: BrowserWindowLayouts(defaults: nil)
        )
        windowState.captureSidebar(
            width: Double(MobileBrowserRootLayout.defaultRegularSidebarWidth),
            isPresented: true
        )
        cloudSync = .isolated(core: browser.core)
        passkeyAccess = BrowserPasskeyAccessController(
            core: browser.core,
            capabilityCheck: { true },
            deviceConfigurationCheck: { .configured },
            authorizationCheck: { .authorized },
            authorizationRequester: { .authorized }
        )
    }
}
