import Foundation

/// A WebKit download no person started, from `origin`, waiting on the site's
/// automatic-download choice. The page it came from asks the person when the
/// rule says to.
@MainActor
struct WebKitAutomaticDownloadRequest: AutomaticDownloadActionPerformer {
    // MARK: - Variables

    let page: WebKitEnginePage?
    let origin: SiteOrigin

    // MARK: - Actions - Settling

    func allowDownload() async -> Bool { true }

    func denyDownload() async -> Bool { false }

    func requestDownloadPermission() async -> Bool {
        guard let page else { return false }
        return await page.ask(
            PermissionQuestion(permission: .automaticDownloads, origin: origin, topLevelOrigin: origin))
    }
}
