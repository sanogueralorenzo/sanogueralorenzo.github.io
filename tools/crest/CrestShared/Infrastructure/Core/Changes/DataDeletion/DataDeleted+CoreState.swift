import Foundation

extension DataDeleted {
    /// A data deletion's end changes no model: `CrestCore.deleteData` hears it.
    @MainActor func apply(to state: CoreState) {}

    @MainActor func apply(to core: CrestCore, in batch: inout CoreChangeBatch) {
        batch.notificationAccessChanged = true
        apply(to: core.state)
        batch.dataDeleted.append(self)
    }
}
