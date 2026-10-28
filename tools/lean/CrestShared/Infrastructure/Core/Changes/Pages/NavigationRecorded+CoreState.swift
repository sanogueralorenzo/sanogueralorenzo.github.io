import Foundation

extension NavigationRecorded {
    /// A recorded navigation changes no page: the session changes before it
    /// carry what it recorded, and `CrestCore` tells the engines' observers.
    @MainActor func apply(to state: CoreState) {}

    @MainActor func apply(to core: CrestCore, in batch: inout CoreChangeBatch) {
        apply(to: core.state)
        batch.pageRecords.navigations.append(self)
    }
}
