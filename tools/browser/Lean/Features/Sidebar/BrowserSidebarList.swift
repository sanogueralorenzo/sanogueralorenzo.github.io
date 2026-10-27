import SwiftUI

struct BrowserSidebarList: View {
    let store: BrowserStore
    let placement: BrowserTab.Placement
    var parentID: UUID?
    var depth = 0
    var body: some View {
        ForEach(store.activeSpace.sidebarEntries(parentID: parentID, placement: placement)) { entry in
            switch entry.kind {
            case .folder(let folder):
                AnyView(BrowserFolderRow(folder: folder, store: store, depth: depth))
            case .tab(let tab):
                BrowserSidebarItem(tab: tab, store: store, depth: depth)
            }
        }
    }
}
