import AppKit
import Foundation

extension BrowserPage: BrowserDesktopWebViewMenuHost {
    var opensLinksInCurrentSpace: Bool { navigationContext != nil }

    /// Answers the menu WebKit is building right now.
    ///
    /// A report can never be inherited by a later menu. The shared page action
    /// builder decides which captured link and selection actions are available.
    func takeMenuContext() -> BrowserDesktopWebViewMenuContext? {
        guard let captured = linkContextCapture.take() else { return nil }
        return BrowserDesktopWebViewMenuContext(
            linkURL: captured.linkURL, imageDownloadURL: captured.imageURL,
            selectionText: captured.selectionText, isEditable: captured.isEditable)
    }

    func downloadImage(from url: URL) {
        let request = URLRequest(url: url)
        Task { @MainActor [weak self] in
            guard let self, let webView = webKitView else { return }
            let download = await webView.startDownload(using: request)
            guard !Task.isCancelled else {
                _ = await download.cancel()
                return
            }
            startDownload(download, in: webView, isUserInitiated: true)
        }
    }

    func discardSplitViewLinkCapture() {
        linkContextCapture.clear()
    }
}
