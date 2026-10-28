import Foundation

/// The person cancelled choosing where a download's file goes.
struct BrowserDownloadDestinationCancelled: BrowserPlatformDownloadResolution {
    // MARK: - Actions - Downloads

    @MainActor func answer(_ asked: DownloadDestinationAsked, for prompts: BrowserDownloadPrompts) {
        prompts.answer(AnswerDownloadDestination(promptID: asked.promptID, path: nil))
    }

    func abandon() {}

    @MainActor func save(_ data: Data, as itemID: UUID, from originatingURL: URL, in center: BrowserDownloadCenter) {
        center.send(CancelDownload(downloadID: itemID, message: "Canceled."))
    }
}
