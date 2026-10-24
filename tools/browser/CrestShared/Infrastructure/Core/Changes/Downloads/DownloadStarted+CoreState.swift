import Foundation

extension DownloadStarted {
    /// A download that started changes no state of its own: its record
    /// arrives as a change of its own, and the window hosting the page it
    /// started on hears of it once the batch is applied.
    @MainActor func apply(to state: CoreState) {}

    @MainActor func apply(to core: CrestCore, in batch: inout CoreChangeBatch) {
        apply(to: core.state)
        batch.startedDownloads.append(self)
    }
}
