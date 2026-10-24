import SwiftUI

struct MobileBrowserSidebarPresentation<Content: View>: View {
    let configuration: MobileBrowserSidebarPresentationConfiguration
    let content: Content

    init(
        configuration: MobileBrowserSidebarPresentationConfiguration,
        @ViewBuilder content: () -> Content
    ) {
        self.configuration = configuration
        self.content = content()
    }

    var body: some View {
        content
            .environment(\.colorScheme, configuration.selectedColorScheme)
            .sheet(item: configuration.presentedSpaceSheet) { request in
                switch request.surface.kind {
                case .archive:
                    MobileArchiveView(
                        browser: configuration.browser,
                        assignment: request.assignment,
                        spaceAccess: configuration.spaceAccess,
                        selectTab: configuration.selectTab
                    )
                case .history:
                    MobileHistoryView(
                        browser: configuration.browser,
                        assignment: request.assignment,
                        spaceAccess: configuration.spaceAccess,
                        openURL: configuration.openURL
                    )
                case .downloads:
                    MobileDownloadsView(
                        browser: configuration.browser,
                        pages: configuration.pages,
                        assignment: request.assignment,
                        spaceAccess: configuration.spaceAccess
                    )
                }
            }
            .sheet(isPresented: configuration.showsPasswords) {
                MobilePasswordSettingsView(
                    browser: configuration.browser,
                    spaceAccess: configuration.spaceAccess
                )
            }
            .onChange(of: configuration.selectedSpaceAssignment) {
                _,
                assignment in
                guard let request = configuration.presentedSpaceSheet.wrappedValue,
                    request.assignment != assignment
                else { return }
                configuration.presentedSpaceSheet.wrappedValue = nil
            }
    }
}
