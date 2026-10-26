import Foundation

extension TransientPageClosed {
    /// The page stays in `state` until whatever shows it lets it go; its
    /// owner hears of it through `CrestCore.followClosedTransientPages`.
    @MainActor func apply(to state: CoreState) {}

    @MainActor func apply(to core: CrestCore, in batch: inout CoreChangeBatch) {
        apply(to: core.state)
        batch.closedTransientPages.append(self)
    }
}
