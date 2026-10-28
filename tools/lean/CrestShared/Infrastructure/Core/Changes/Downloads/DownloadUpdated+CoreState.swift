import Foundation

extension DownloadUpdated {
    @MainActor func apply(to state: CoreState) {
        if let index = state.downloads.firstIndex(where: { $0.id == download.id }) {
            state.downloads[index] = download
        } else {
            state.downloads.insert(download, at: min(max(position, 0), state.downloads.count))
        }
    }

    @MainActor func apply(to core: CrestCore, in batch: inout CoreChangeBatch) {
        apply(to: core.state)
        batch.downloads.append(download)
    }
}
