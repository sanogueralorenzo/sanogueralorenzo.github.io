import Foundation

extension PageUnloaded {
    /// An unloaded page is removed by the `PageRemoved` before it; its owner
    /// hears of it through `CrestCore.followUnloadedPages`.
    @MainActor func apply(to state: CoreState) {}

    @MainActor func apply(to core: CrestCore, in batch: inout CoreChangeBatch) {
        apply(to: core.state)
        batch.unloadedPages.append(self)
    }
}
