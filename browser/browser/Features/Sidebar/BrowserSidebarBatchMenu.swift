import SwiftUI

struct BrowserSidebarBatchMenu: View {
    let store: BrowserStore
    private var ids: [UUID] { store.selectedActionTabIDs }
    private var hasFolders: Bool { !store.selectedFolders.isEmpty }
    private var includesLiveFolder: Bool {
        store.activeSpace.liveFolders.contains { store.selectedFolders.contains($0.id) }
    }
    private var pinnedOnly: Bool {
        !ids.isEmpty
            && ids.allSatisfy { id in store.activeSpace.tabs.contains { $0.id == id && $0.placement == .pinned } }
    }
    var body: some View {
        let count = hasFolders ? store.selectionRootFolders.count + store.selectedLooseTabIDs.count : ids.count
        Text(
            hasFolders
                ? "\(count) \(count == 1 ? "item" : "items") selected"
                : "\(count) \(count == 1 ? "tab" : "tabs") selected"
        ).disabled(true)
        Divider()
        if !hasFolders {
            Button("Copy Link URLs", systemImage: "link") { store.copySelectedLinks() }
            Divider()
            Button(
                pinnedOnly ? "Unpin \(ids.count) Tabs" : "Pin \(ids.count) Tabs",
                systemImage: pinnedOnly ? "pin.slash" : "pin"
            ) {
                store.fileSidebarSelection(as: pinnedOnly ? .current : .pinned)
            }
        }
        if hasFolders || !pinnedOnly {
            Button("Move to Tabs", systemImage: "rectangle.stack") { store.fileSidebarSelection(as: .current) }
                .disabled(includesLiveFolder)
        }
        Button("Move to Saved", systemImage: "bookmark") { store.fileSidebarSelection(as: .saved) }
            .disabled(includesLiveFolder)
        Menu("Move to Folder", systemImage: "folder") {
            Button("New Folder in Tabs") { fileInNewFolder(.current) }
            Button("New Folder in Saved") { fileInNewFolder(.saved) }
            ForEach(
                store.activeSpace.folders.filter { folder in
                    folder.kind == .regular && !store.selectedFolders.contains(folder.id)
                        && !store.selectionCovers(folder.parentID)
                }
            ) { folder in
                Button(folder.title) { store.fileSidebarSelection(as: folder.placement ?? .saved, folderID: folder.id) }
            }
        }
        .disabled(includesLiveFolder)
        if !hasFolders {
            let source = store.activeSpace
            let destinations = store.session.spaces.filter { $0.id != source.id && source.canMoveItems(to: $0) }
            if !destinations.isEmpty {
                Menu("Move to Space", systemImage: "square.grid.2x2") {
                    ForEach(destinations) { space in
                        Button(space.name) { store.moveTabs(ids, to: space.id) }
                    }
                }
            }
            Button("Combine in Split View", systemImage: "rectangle.split.2x1") {
                store.combineTabs(ids)
            }.disabled(
                ids.count < 2 || ids.count > 4
                    || ids.contains { id in store.activeSpace.tabs.contains { $0.id == id && $0.isSettings } })
            if store.activeSpace.splits.contains(where: { !Set($0.tabIDs).isDisjoint(with: ids) }) {
                Button("Separate Selected Splits", systemImage: "rectangle.split.2x1.slash") {
                    for id in ids { store.detachFromSplits(id) }
                    store.changed()
                }
            }
            Divider()
            Button("Duplicate \(ids.count) Tabs", systemImage: "plus.square.on.square") { store.duplicateTabs(ids) }
            Button("Archive Selected Tabs", systemImage: "archivebox") {
                store.requestDeleteTabs(
                    ids.filter { id in store.activeSpace.tabs.contains { $0.id == id && $0.placement == .current } })
            }
            Button("Delete \(ids.count) Tabs", systemImage: "trash", role: .destructive) {
                store.deleteSidebarSelection()
            }
        }
        Divider()
        Button(hasFolders ? "Select All Items" : "Select All Tabs") {
            store.selectedSidebarItems = Set(store.sidebarSelectionUnits.flatMap { $0 })
        }
        Button("Deselect All") { store.clearSidebarSelection() }
    }
    private func fileInNewFolder(_ placement: BrowserTab.Placement) {
        store.createSidebarFolder(
            containing: BrowserDragPayload(
                kind: .tabs, spaceID: store.activeSpace.id,
                ids: store.selectedLooseTabIDs, folderIDs: store.selectionRootFolders,
                activeTabID: store.selectedTab?.id),
            placement: placement)
    }
}
