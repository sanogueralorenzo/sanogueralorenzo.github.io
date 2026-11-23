import AppKit
import WebKit

struct BrowserPendingDownload: Identifiable {
    let id = UUID()
    let record: BrowserDownloadRecord
}

extension BrowserSessionOwner {
    func activeDownloadRequests(in spaceID: UUID? = nil) -> [UUID: UUID] {
        var requests = Dictionary(
            uniqueKeysWithValues: downloads.values.filter {
                $0.isActive && (spaceID == nil || $0.spaceID == spaceID)
            }.map { ($0.id, $0.requestID) })
        for request in pendingDownloads.values where spaceID == nil || request.record.spaceID == spaceID {
            requests[request.record.id] = request.id
        }
        return requests
    }

    func downloadRequestsMatch(_ expected: [UUID: UUID], in spaceID: UUID? = nil) -> Bool {
        activeDownloadRequests(in: spaceID).allSatisfy { expected[$0.key] == $0.value }
    }

    func cancelPendingDownload(_ id: UUID) {
        guard let pending = pendingDownloads.removeValue(forKey: id),
            let index = session.downloads.firstIndex(where: { $0.id == id && $0.spaceID == pending.record.spaceID })
        else { return }
        session.downloads[index].status = .cancelled
        session.downloads[index].resumeData = nil
        session.downloads[index].error = nil
        changed()
    }

    func downloadWindow(preferred id: UUID?) -> NSWindow? {
        id.flatMap { contexts[$0]?.window }
            ?? activeWindowID.flatMap { contexts[$0]?.window }
    }

    func finishDownloadRequest(
        _ download: WKDownload, pending: BrowserPendingDownload, view: WKWebView, windowID: UUID
    ) {
        if downloads[ObjectIdentifier(download)] != nil { return }
        let id = pending.record.id
        guard pendingDownloads[id]?.id == pending.id else {
            download.cancel { _ in }
            return
        }
        pendingDownloads[id] = nil
        guard
            session.downloads.contains(where: {
                $0.id == id && $0.spaceID == pending.record.spaceID && $0.status == .choosing
            })
        else {
            download.cancel { _ in }
            return
        }
        let job = beginDownload(
            download, spaceID: pending.record.spaceID, windowID: windowID, restoring: id, requestID: pending.id)
        job?.downloadView = view
    }

    @discardableResult
    func beginDownload(
        _ download: WKDownload, spaceID: UUID, windowID: UUID?, restoring id: UUID? = nil, requestID: UUID = UUID()
    ) -> BrowserDownload? {
        guard session.spaces.contains(where: { $0.id == spaceID }) else {
            download.cancel { _ in }
            return nil
        }
        if let job = downloads[ObjectIdentifier(download)] { return job }
        if let id, activeDownloadRequests()[id] != nil {
            download.cancel { _ in }
            return nil
        }
        let job = BrowserDownload(
            download: download, owner: self, spaceID: spaceID, windowID: windowID, restoring: id, requestID: requestID)
        downloads[ObjectIdentifier(download)] = job
        runtimeRevision &+= 1
        return job
    }
}

extension BrowserStore {
    func prepareToDeleteSpace(_ spaceID: UUID) async -> Bool {
        let requests = owner.activeDownloadRequests(in: spaceID)
        guard !requests.isEmpty else { return true }
        let alert = NSAlert()
        alert.messageText = "Downloads are still running"
        alert.informativeText = "Deleting this Space will cancel its downloads."
        alert.addButton(withTitle: "Keep Space")
        alert.addButton(withTitle: "Cancel Downloads and Delete")
        guard await BrowserDialogs.ask(alert, in: window) == .alertSecondButtonReturn,
            owner.downloadRequestsMatch(requests, in: spaceID)
        else { return false }
        for id in requests.keys { cancelDownload(id) }
        return owner.activeDownloadRequests(in: spaceID).isEmpty
    }

    func resumeDownload(_ record: BrowserDownloadRecord) {
        guard let pending = prepareDownload(record.id, resuming: true), let data = pending.record.resumeData else {
            return
        }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = profile(for: pending.record.spaceID)
        BrowserWebKitDefaults.apply(to: config.preferences)
        let view = WKWebView(frame: .zero, configuration: config)
        view.resumeDownload(fromResumeData: data) { [weak owner, view, id] download in
            guard let owner else {
                download.cancel { _ in }
                return
            }
            owner.finishDownloadRequest(download, pending: pending, view: view, windowID: id)
        }
    }

    func restartDownload(_ record: BrowserDownloadRecord) {
        guard let pending = prepareDownload(record.id, resuming: false), let url = pending.record.source else { return }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = profile(for: pending.record.spaceID)
        BrowserWebKitDefaults.apply(to: config.preferences)
        let view = WKWebView(frame: .zero, configuration: config)
        view.startDownload(using: URLRequest(url: url)) { [weak owner, view, id] download in
            guard let owner else {
                download.cancel { _ in }
                return
            }
            owner.finishDownloadRequest(download, pending: pending, view: view, windowID: id)
        }
    }

    private func prepareDownload(_ id: UUID, resuming: Bool) -> BrowserPendingDownload? {
        guard !isClosed, let index = session.downloads.firstIndex(where: { $0.id == id }),
            ![.running, .choosing].contains(session.downloads[index].status),
            owner.activeDownloadRequests()[id] == nil,
            session.spaces.contains(where: { $0.id == session.downloads[index].spaceID })
        else { return nil }
        if resuming {
            guard session.downloads[index].resumeData != nil else {
                showNotice("This download cannot resume. Open the source page to start it again.")
                return nil
            }
        } else {
            guard session.downloads[index].requestMethod == "GET", let url = session.downloads[index].source,
                ["http", "https"].contains(url.scheme ?? "")
            else { return nil }
            session.downloads[index].destination = nil
            session.downloads[index].destinationBookmark = nil
            session.downloads[index].replacementIdentity = nil
            session.downloads[index].received = 0
            session.downloads[index].expected = 0
            session.downloads[index].resumeData = nil
        }
        let pending = BrowserPendingDownload(record: session.downloads[index])
        owner.pendingDownloads[id] = pending
        session.downloads[index].status = .choosing
        session.downloads[index].error = nil
        changed()
        return pending
    }

    func cancelDownload(_ id: UUID) {
        owner.cancelPendingDownload(id)
        activeDownloads.first { $0.id == id }?.cancel()
    }

    func openDownload(_ record: BrowserDownloadRecord) {
        guard record.status == .completed, let url = record.destination else { return }
        NSWorkspace.shared.open(url)
    }

    func chooseDownloadDirectory(in requestedSpaceID: UUID? = nil) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        let spaceID = requestedSpaceID ?? activeSpace.id
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
