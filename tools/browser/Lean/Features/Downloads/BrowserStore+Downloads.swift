import AppKit
import WebKit

extension BrowserStore {
    func prepareToDeleteSpace(_ spaceID: UUID) async -> Bool {
        let jobs = activeDownloads.filter { $0.spaceID == spaceID }
        guard !jobs.isEmpty else { return true }
        let alert = NSAlert()
        alert.messageText = "Downloads are still running"
        alert.informativeText = "Deleting this Space will cancel its downloads."
        alert.addButton(withTitle: "Keep Space")
        alert.addButton(withTitle: "Cancel Downloads and Delete")
        guard await BrowserDialogs.ask(alert, in: window) == .alertSecondButtonReturn else { return false }
        for job in jobs { job.cancel() }
        return true
    }

    func resumeDownload(_ record: BrowserDownloadRecord) {
        guard session.spaces.contains(where: { $0.id == record.spaceID }), let data = record.resumeData else {
            showNotice("This download cannot resume. Open the source page to start it again.")
            return
        }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = profile(for: record.spaceID)
        configureWebKit(config.preferences)
        let view = WKWebView(frame: .zero, configuration: config)
        view.resumeDownload(fromResumeData: data) { [weak self, view] download in
            self?.beginDownload(download, spaceID: record.spaceID, restoring: record.id)
            self?.downloads[ObjectIdentifier(download)]?.downloadView = view
        }
    }

    func restartDownload(_ record: BrowserDownloadRecord) {
        guard record.requestMethod == "GET", let url = record.source, ["http", "https"].contains(url.scheme ?? ""),
            session.spaces.contains(where: { $0.id == record.spaceID })
        else { return }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = profile(for: record.spaceID)
        configureWebKit(config.preferences)
        let view = WKWebView(frame: .zero, configuration: config)
        if let i = session.downloads.firstIndex(where: { $0.id == record.id }) {
            session.downloads[i].destination = nil
            session.downloads[i].destinationBookmark = nil
            session.downloads[i].received = 0
            session.downloads[i].expected = 0
        }
        view.startDownload(using: URLRequest(url: url)) { [weak self, view] download in
            self?.beginDownload(download, spaceID: record.spaceID, restoring: record.id)
            self?.downloads[ObjectIdentifier(download)]?.downloadView = view
        }
    }

    func openDownload(_ record: BrowserDownloadRecord) {
        guard record.status == .completed, let url = record.destination else { return }
        NSWorkspace.shared.open(url)
    }

    func chooseDownloadDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        let spaceID = activeSpace.id
        guard let window else { return }
        panel.beginSheetModal(for: window) { result in
            guard result == .OK, let url = panel.url,
                let index = self.session.spaces.firstIndex(where: { $0.id == spaceID })
            else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            self.session.spaces[index].downloadDirectory = try? url.bookmarkData(
                options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            self.changed()
        }
    }

    func revealDownload(_ record: BrowserDownloadRecord) {
        guard record.status == .completed, let url = record.destination else { return }
        var stale = false
        let scoped =
            record.destinationBookmark.flatMap {
                try? URL(
                    resolvingBookmarkData: $0,
                    options: [.withSecurityScope], bookmarkDataIsStale: &stale)
            } ?? url
        let access = scoped.startAccessingSecurityScopedResource()
        NSWorkspace.shared.activateFileViewerSelecting([url])
        if access { scoped.stopAccessingSecurityScopedResource() }
    }
}
