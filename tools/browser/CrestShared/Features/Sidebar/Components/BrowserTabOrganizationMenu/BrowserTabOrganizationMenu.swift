import SwiftUI

struct BrowserTabOrganizationMenu: View {

    let tab: TabStateModel
    let context: BrowserSidebarListContext
    let assignment: BrowserTabRuntimeAssignment
    var isLoaded = true
    var renameTab: (() -> Void)? = nil
    var changeIcon: (() -> Void)? = nil

    @Environment(\.browserInteractionCapabilities) private var capabilities

    var body: some View {
        Group {
            if capabilities.allowsMultiSelection,
                let request = BrowserSidebarSelection.capture(for: .tab(tab.id), in: context.browser)
            {
                BrowserTabBatchMenu(
                    request: request, browser: context.browser, spaceAccess: context.spaceAccess,
                    unload: { context.unload($0) })
            } else {
                BrowserTabOrganizationMenuContent(menu: self)
                BrowserSidebarSelectionMenu(item: .tab(tab.id), browser: context.browser)
            }
        }
        .crestMenuActionLabelStyle()
    }
}
