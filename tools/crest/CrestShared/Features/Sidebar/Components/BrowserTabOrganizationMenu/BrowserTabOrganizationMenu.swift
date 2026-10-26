import SwiftUI

struct BrowserTabOrganizationMenu: View {

    let tab: TabStateModel
    let context: BrowserSidebarListContext
    let assignment: BrowserTabRuntimeAssignment
    var renameTab: (() -> Void)? = nil

    @Environment(\.browserInteractionCapabilities) private var capabilities

    var body: some View {
        Group {
            if capabilities.allowsMultiSelection,
                let request = BrowserSidebarSelection.capture(for: .tab(tab.id), in: context.browser)
            {
                BrowserTabBatchMenu(
                    request: request, browser: context.browser)
            } else {
                BrowserTabOrganizationMenuContent(menu: self)
                BrowserSidebarSelectionMenu(item: .tab(tab.id), browser: context.browser)
            }
        }
        .crestMenuActionLabelStyle()
    }
}
