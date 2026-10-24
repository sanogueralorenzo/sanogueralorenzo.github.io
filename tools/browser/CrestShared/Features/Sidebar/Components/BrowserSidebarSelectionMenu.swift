import SwiftUI

struct BrowserSidebarSelectionMenu: View {

    let item: BrowserSelectionItemID
    let browser: BrowserStore
    @Environment(\.browserInteractionCapabilities) private var capabilities

    var body: some View {
        if capabilities.allowsMultiSelection {
            Divider()
            Button("Add to Selection") {
                browser.tabMultiSelection.click(
                    item,
                    units: BrowserSidebarSelection.itemUnits(in: browser), command: true)
            }
            Button {
                browser.tabMultiSelection.selectAll(
                    units: BrowserSidebarSelection.itemUnits(in: browser))
            } label: {
                switch item {
                case .tab: Text("Select All Tabs")
                case .folder: Text("Select All Items")
                }
            }
        }
    }
}
