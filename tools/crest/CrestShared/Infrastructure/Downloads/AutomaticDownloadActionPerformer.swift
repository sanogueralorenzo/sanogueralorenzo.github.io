import Foundation

/// Settles a download no person started, as the core's automatic-download
/// rule says: one method per action the rule answers, each saying whether the
/// download goes on. An action the core adds fails to compile until every
/// performer takes it.
@MainActor
protocol AutomaticDownloadActionPerformer {
    func allowDownload() async -> Bool
    func denyDownload() async -> Bool
    func requestDownloadPermission() async -> Bool
}
