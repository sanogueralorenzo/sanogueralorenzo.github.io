import Foundation

extension OfferedPageAdopted {
    /// An adopted page arrives through the `PageOpened` before it; the window
    /// that hosts it hears of it through `CrestCore.followAdoptedPages`.
    @MainActor func apply(to state: CoreState) {}

    @MainActor func apply(to core: CrestCore, in batch: inout CoreChangeBatch) {
        apply(to: core.state)
        batch.adoptedPages.append(self)
    }
}
