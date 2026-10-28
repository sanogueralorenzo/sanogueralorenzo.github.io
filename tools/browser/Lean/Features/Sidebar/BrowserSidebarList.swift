import SwiftUI

struct BrowserSidebarList: View {
    @Environment(\.sidebarSpaceID) private var presentedSpaceID
    private var space: BrowserSpace { store.sidebarSpace(presentedSpaceID) }
    let store: BrowserStore
    let placement: BrowserTab.Placement
    var parentID: UUID?
    var depth = 0
    var keeping: UUID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let entries = space.sidebarEntries(parentID: parentID, placement: placement, keeping: keeping)
        VStack(spacing: 2) {
            ForEach(entries) { entry in
                switch entry.kind {
                case .folder(let folder):
                    AnyView(BrowserFolderRow(folder: folder, store: store, depth: depth, inheritedKeptTabID: keeping))
                        .transition(.opacity)
                case .tab(let tab):
                    BrowserSidebarItem(tab: tab, store: store, depth: depth)
                        .geometryGroup()
                        .transition(depth > 0 ? .opacity.combined(with: .move(edge: .top)) : .opacity)
                }
            }
        }
        .animation(LeanMotion.collection.unlessReducingMotion(reduceMotion), value: entries.map(\.id))
    }
}
