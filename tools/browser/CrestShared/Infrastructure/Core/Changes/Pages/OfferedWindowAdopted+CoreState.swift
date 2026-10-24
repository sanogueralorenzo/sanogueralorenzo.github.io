import Foundation

extension OfferedWindowAdopted {
    /// An adopted window's page arrives through the `PageOpened` before it;
    /// the window that hosts it hears of it through
    /// `CrestCore.followAdoptedWindows`.
    @MainActor func apply(to state: CoreState) {}

    @MainActor func apply(to core: CrestCore, in batch: inout CoreChangeBatch) {
        apply(to: core.state)
        batch.adoptedWindows.append(self)
    }
}
