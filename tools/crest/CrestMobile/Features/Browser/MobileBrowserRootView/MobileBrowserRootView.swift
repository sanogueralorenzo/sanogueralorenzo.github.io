import SwiftUI

struct MobileBrowserRootView: View {
    private let dataDeleter: any BrowserSpaceDataDeleting
    private let transientBrowsing: BrowserTransientBrowsingCoordinator
    private let suspendsCompactPagePresentation: Bool
    private let togglePrivateBrowsing: () -> Void
    private let closePrivateBrowsing: () -> Void

    @State private var model: MobileBrowserRootModel

    init(
        browser: BrowserStore,
        pages: MobileBrowserPageStore,
        dataDeleter: any BrowserSpaceDataDeleting,
        navigation: MobileBrowserNavigationState,
        transientBrowsing: BrowserTransientBrowsingCoordinator,
        spaceAccess: BrowserSpaceAccessController = BrowserSpaceAccessController(),
        windowState: BrowserWindowStateStore? = nil,
        suspendsCompactPagePresentation: Bool = false,
        startupBehavior: StartupBehavior = .showStartPage,
        togglePrivateBrowsing: @escaping () -> Void,
        closePrivateBrowsing: @escaping () -> Void
    ) {
        self.dataDeleter = dataDeleter
        self.transientBrowsing = transientBrowsing
        self.suspendsCompactPagePresentation = suspendsCompactPagePresentation
        self.togglePrivateBrowsing = togglePrivateBrowsing
        self.closePrivateBrowsing = closePrivateBrowsing
        let fallbackWidth =
            windowState?.sidebarWidth.map { CGFloat($0) }
            ?? BrowserSidebarWidthPreference.value(
                forKey: MobileBrowserRootPreferences.adaptiveSidebarWidthKey,
                default: MobileBrowserRootLayout.defaultRegularSidebarWidth
            )
        _model = State(
            initialValue: MobileBrowserRootModel(
                browser: browser,
                pages: pages,
                navigation: navigation,
                spaceAccess: spaceAccess,
                windowState: windowState,
                startupBehavior: startupBehavior,
                persistedSidebarWidth:
                    windowState?.sidebarWidth.map { CGFloat($0) }
                    ?? fallbackWidth
            )
        )
    }

    var body: some View {
        MobileBrowserRootContent(
            model: model,
            dataDeleter: dataDeleter,
            transientBrowsing: transientBrowsing,
            suspendsCompactPagePresentation: suspendsCompactPagePresentation,
            togglePrivateBrowsing: togglePrivateBrowsing,
            closePrivateBrowsing: closePrivateBrowsing
        )
        // The side toolbar sits over the Space's atmosphere, so its glass
        // follows the Space's tone as the sidebar's controls do.
        .modifier(MobileBrowserSideToolbarHost(browser: model.browser))
        .environment(model.sidebarInteraction)
        .environment(\.browserNativeTabs, model.pages.nativeTabs)
        .environment(
            \.browserSettingsTabContent,
            BrowserSettingsTabContent { runtime in
                MobileBrowserSettingsView(
                    browser: model.browser, pages: model.pages, spaceAccess: model.spaceAccess,
                    dataDeleter: dataDeleter,
                    state: runtime.model(MobileBrowserSettingsState.self, make: MobileBrowserSettingsState.init),
                    isInTab: true,
                    liveSpaceSelection: BrowserSettingsLiveSpaceSelection { id in
                        model.settings.selectLiveSpace(id, matching: runtime.assignment)
                    })
            }
        )
        .environment(
            \.browserNativeTabActions,
            BrowserNativeTabActions(
                browser: model.browser, spaceAccess: model.spaceAccess,
                didOpenURL: { model.pages.select() }))
    }
}

#Preview(
    "Mobile Browser - Compact",
    traits: .fixedLayout(width: 393, height: 852)
) {
    let fixture = MobileBrowserPreviewFixture()
    MobileBrowserRootView(
        browser: fixture.browser,
        pages: fixture.pages,
        dataDeleter: fixture.pages,
        navigation: MobileBrowserNavigationState(),
        transientBrowsing: BrowserTransientBrowsingCoordinator(),
        spaceAccess: fixture.spaceAccess,
        windowState: fixture.windowState,
        togglePrivateBrowsing: {},
        closePrivateBrowsing: {}
    )
}

#Preview(
    "Mobile Browser - Expanded",
    traits: .fixedLayout(width: 1_024, height: 768)
) {
    let fixture = MobileBrowserPreviewFixture()
    MobileBrowserRootView(
        browser: fixture.browser,
        pages: fixture.pages,
        dataDeleter: fixture.pages,
        navigation: MobileBrowserNavigationState(),
        transientBrowsing: BrowserTransientBrowsingCoordinator(),
        spaceAccess: fixture.spaceAccess,
        windowState: fixture.windowState,
        togglePrivateBrowsing: {},
        closePrivateBrowsing: {}
    )
}
