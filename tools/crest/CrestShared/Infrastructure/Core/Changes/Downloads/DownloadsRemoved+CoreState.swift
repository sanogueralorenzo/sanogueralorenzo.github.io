import Foundation

extension DownloadsRemoved {
    @MainActor func apply(to state: CoreState) {
        let removed = Set(downloadIDs)
        state.downloads.removeAll { removed.contains($0.id) }
    }
}
