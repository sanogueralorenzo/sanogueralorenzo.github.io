import AppKit
import Foundation

extension BrowserPage {
    // MARK: - Actions - Downloads

    /// Shows the download the core saw start on this page leaving it for the
    /// downloads list: from the pointer, or else from where the page's engine
    /// saw the person start it. Whichever engine runs the download, this is
    /// where its window hears of it.
    func showDownloadStarted(_ started: DownloadStarted) {
        let engineSource = startedDownloadSource
        startedDownloadSource = nil
        guard let source = BrowserMacDownloadFeedbackSource.capture(in: nativeView) ?? engineSource else { return }
        downloadCenter.presentFeedback(
            BrowserDownloadFeedbackEvent(
                id: started.downloadID, profileID: profileID, spaceID: spaceID,
                filename: downloadCenter.item(started.downloadID)?.filename ?? "download", source: source))
    }
}
