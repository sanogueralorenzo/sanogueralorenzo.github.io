import Foundation

/// The platform chose where a download's file goes.
struct BrowserDownloadDestinationChosen: BrowserPlatformDownloadResolution {
    // MARK: - Variables

    let url: URL
    /// The folder access the write needs, when it needs one.
    let securityScopedURL: URL?

    // MARK: - Actions - Downloads

    @MainActor func answer(_ asked: DownloadDestinationAsked, for prompts: BrowserDownloadPrompts) {
        if let securityScopedURL { prompts.downloadFolders[asked.downloadID] = securityScopedURL }
        prompts.answer(AnswerDownloadDestination(promptID: asked.promptID, path: url.path))
    }

    func abandon() {
        securityScopedURL?.stopAccessingSecurityScopedResource()
    }

    @MainActor func save(_ data: Data, as itemID: UUID, from originatingURL: URL, in center: BrowserDownloadCenter) {
        let scoped = securityScopedURL?.startAccessingSecurityScopedResource() ?? false
        defer { if scoped { securityScopedURL?.stopAccessingSecurityScopedResource() } }
        do {
            try center.saveDataToDestination(data, itemID: itemID, destination: url, originatingURL: originatingURL)
            center.send(FinishDownload(downloadID: itemID, finalByteCount: Int64(data.count)))
        } catch {
            center.send(FailDownload(downloadID: itemID, reason: .fileAccess, message: error.localizedDescription))
        }
    }
}
