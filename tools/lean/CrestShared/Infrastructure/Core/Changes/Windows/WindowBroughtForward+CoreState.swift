import Foundation

extension WindowBroughtForward {
    /// What the window shows arrives through the `WindowChanged` before it;
    /// the window itself comes forward through `CrestCore.followWindowsBroughtForward`.
    @MainActor func apply(to state: CoreState) {}

    @MainActor func apply(to core: CrestCore, in batch: inout CoreChangeBatch) {
        apply(to: core.state)
        batch.broughtForward.append(self)
    }
}
