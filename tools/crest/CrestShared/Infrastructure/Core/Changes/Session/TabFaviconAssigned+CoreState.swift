import Foundation

extension TabFaviconAssigned {
    @MainActor func apply(to state: CoreState) {
        if state.workspaces[workspaceID]?.holdsOpen(tabID: tabID) == true {
            state.favicons.assign(adopts: adopts, to: tabID, in: workspaceID, from: pageID)
        }
        state.touch(workspaceID)
    }

    @MainActor func apply(to core: CrestCore, in batch: inout CoreChangeBatch) {
        apply(to: core.state)
        if pageID != nil { batch.pageRecords.icons.append(self) }
    }
}
