import SwiftUI

struct MobileBrowserRootView: View {
    private let dataDeleter: any BrowserSpaceDataDeleting
    private let togglePrivateBrowsing: () -> Void
    private let closePrivateBrowsing: () -> Void

    @State private var model: MobileBrowserRootModel

    init(
        browser: BrowserStore,
        pages: MobileBrowserPageStore,
        dataDeleter: any BrowserSpaceDataDeleting,
        navigation: MobileBrowserNavigationState,

        windowState: BrowserWindowStateStore? = nil,
        togglePrivateBrowsing: @escaping () -> Void,
        closePrivateBrowsing: @escaping () -> Void
    ) {
        self.dataDeleter = dataDeleter
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
                windowState: windowState,
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

            togglePrivateBrowsing: togglePrivateBrowsing,
            closePrivateBrowsing: closePrivateBrowsing
        )
        // The side toolbar sits over the Space's atmosphere, so its glass
        // follows the Space's tone as the sidebar's controls do.
        .modifier(MobileBrowserSideToolbarHost(browser: model.browser))
        .environment(\.browserShowsInlineShortcuts, false)
        .environment(\.browserShortcutBindings, model.browser.core.state.shortcuts)
        .environment(model.sidebarInteraction)
        .environment(\.browserNativeTabs, model.pages.nativeTabs)
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

        windowState: fixture.windowState,
        togglePrivateBrowsing: {},
        closePrivateBrowsing: {}
    )
}
