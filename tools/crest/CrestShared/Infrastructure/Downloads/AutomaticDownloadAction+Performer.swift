import Foundation

extension AutomaticDownloadAction {
    /// Settles the download on `performer`, by its method for this action, and
    /// says whether the download goes on.
    @MainActor func settle(on performer: some AutomaticDownloadActionPerformer) async -> Bool {
        switch kind {
        case .allow: await performer.allowDownload()
        case .deny: await performer.denyDownload()
        case .requestPermission: await performer.requestDownloadPermission()
        }
    }
}
