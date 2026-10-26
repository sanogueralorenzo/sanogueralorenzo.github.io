import Foundation

extension PageRehosted {
    /// The `PageChanged` before it carries the page on its new engine; its
    /// followers hear of the move through `CrestCore.followRehostedPages`.
    @MainActor func apply(to state: CoreState) {}

    @MainActor func apply(to core: CrestCore, in batch: inout CoreChangeBatch) {
        apply(to: core.state)
        batch.rehostedPages.append(self)
    }
}
