import Foundation

extension DownloadRowAction {
    /// What the row's button asks for the download `itemID`. Opening asks once
    /// per destination the person picks, so it has no single request and its
    /// row offers the destinations instead.
    func request(for itemID: UUID) -> BrowserUtilityDownloadAction? {
        switch kind {
        case .retry: .retry(itemID)
        case .cancel: .cancel(itemID)
        case .open: nil
        case .remove: .clear(itemID)
        case .pause: .pause(itemID)
        case .resume: .resume(itemID)
        }
    }
}
