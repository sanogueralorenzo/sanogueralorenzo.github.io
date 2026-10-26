import SwiftUI

struct MobileBrowserSidebarBottomChromeLayout<Content: View>: View {
    let configuration: MobileBrowserSidebarContentConfiguration
    let content: Content

    init(
        configuration: MobileBrowserSidebarContentConfiguration,
        @ViewBuilder content: () -> Content
    ) {
        self.configuration = configuration
        self.content = content()
    }

    var body: some View {
        if showsBottomChrome {
            content
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: 0) {
                        // A top layer over every Space of every profile: mounted
                        // beside the pager and never keyed to the selected Space,
                        // so a Space switch cannot unmount or recreate the deck.
                        if BrowserSidebarWidgetHost.isShown(
                            sidebarIsPresented:
                                configuration.sidebarIsPresented,
                            isPrivateBrowsing: configuration.context.browser
                                .isPrivateBrowsing
                        ) {
                            BrowserSidebarWidgetHost(
                                capabilities: [
                                    .persistentSidebar,
                                    .mediaSessions,
                                ],
                                activateMediaSession: activateMediaSession,
                                ownerFaviconData: ownerFaviconData
                            )
                        }

                        MobileBrowserSidebarBottomChrome(
                            configuration: configuration
                        )
                    }
                }
        } else {
            content
        }
    }

    /// Whether the bottom chrome sits under the content.
    ///
    /// A shell that reserves the inset keeps it whether or not its controls are
    /// on screen. That leaves the selected matched tab destination at the same
    /// resting position throughout page presentation and return.
    private var showsBottomChrome: Bool {
        configuration.reservesBottomChromeInset || configuration.showsBottomSpaceSwitcher
    }

    private func ownerFaviconData(
        _ assignment: BrowserTabRuntimeAssignment
    ) -> Data? {
        let browser = configuration.context.browser
        guard browser.spaceModel(matching: assignment.spaceAssignment)?.tabs.model(assignment.tabID) != nil else {
            return nil
        }
        return browser.core.state.favicons.image(of: assignment.tabID)
    }

    private func activateMediaSession(
        _ assignment: BrowserTabRuntimeAssignment
    ) {
        Task { @MainActor in
            guard
                configuration.pages.containsResidentPage(matching: assignment),
                let space = configuration.context.browser.spaceModel(matching: assignment.spaceAssignment),
                space.tabs.model(assignment.tabID) != nil,
                await configuration.context.spaceAccess.unlock(space)
            else { return }
            configuration.context.selectSpace(assignment.spaceID)
            configuration.selectTab(assignment.tabID)
        }
    }
}
