import SwiftUI

struct BrowserSidebarItem: View {
    let tab: BrowserTab
    let store: BrowserStore
    var pinned = false
    var body: some View {
        if let split = store.activeSpace.splits.first(where: { $0.tabIDs.contains(tab.id) }) {
            if split.tabIDs.first == tab.id {
                VStack(spacing: 2) {
                    ForEach(split.tabIDs, id: \.self) { id in
                        if let member = store.activeSpace.tabs.first(where: { $0.id == id }) {
                            BrowserTabRow(tab: member, store: store, pinned: pinned)
                        }
                    }
                }
                .padding(4)
                .background(LeanBrandTheme.line, in: RoundedRectangle(cornerRadius: 20))
                .contextMenu {
                    Button("Change Split Direction") {
                        store.selectTab(tab.id)
                        store.changeSplitDirection()
                    }
                    Button("Separate All Tabs") {
                        store.selectTab(tab.id)
                        store.leaveSplit()
                    }
                }
            }
        } else {
            BrowserTabRow(tab: tab, store: store, pinned: pinned)
        }
    }
}
