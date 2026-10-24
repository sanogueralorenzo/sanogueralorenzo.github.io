import SwiftUI

struct MobileBrowserSidebarSpaceContent: View {
    let configuration: MobileBrowserSidebarContentConfiguration
    let space: SpaceModel
    let isSelected: Bool

    var body: some View {
        if configuration.utilityPresentationStyle == .inline,
            let utilitySurface = configuration.context.utilityPresentation.surface
        {
            if isSelected {
                BrowserUtilityListContent(
                    surface: utilitySurface,
                    space: space,
                    downloads: configuration.context.pageAccess.downloadCenter
                        .items(for: space.profileID),
                    searchText: configuration.context.utilitySearchText
                        .wrappedValue,
                    filter: configuration.context.utilityFilter.wrappedValue,
                    actions: configuration.context.utilityActions,
                    dismissOnBlankSpace:
                        configuration.context.dismissUtilityOnBlankSpace,
                    favicons: configuration.context.browser.core.state.favicons
                )
            } else {
                Color.clear
            }
        } else {
            MobileBrowserSpacePage(
                space: space,
                browser: configuration.context.browser,
                pages: configuration.pages,
                spaceAccess: configuration.context.spaceAccess,
                capabilities: configuration.context.capabilities,
                tabPromotionNamespace: configuration.tabPromotionNamespace,
                selectTab: configuration.selectTab,
                openNewTab: configuration.openNewTab,
                showHistory: configuration.context.chromeActions.presentHistory,
                showPasswords: showPasswords,
                showSettings: showSettings,
                closePrivateBrowsing: configuration.closePrivateBrowsing,
                compactPageIsFullyPresented:
                    configuration.compactPageIsFullyPresented
            )
        }
    }

    private func showPasswords() {
        configuration.context.chromeActions.presentPasswords?()
    }

    private func showSettings() {
        configuration.context.chromeActions.presentSpaceSettings(BrowserSpaceRuntimeAssignment(space: space))
    }
}
