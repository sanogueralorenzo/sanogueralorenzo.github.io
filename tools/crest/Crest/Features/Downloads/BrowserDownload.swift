import AppKit
import Darwin
import Observation
import WebKit

@MainActor @Observable
final class BrowserDownload: NSObject, WKDownloadDelegate, Identifiable {
    let id: UUID
    let download: WKDownload
    let spaceID: UUID
    var name = "Download"
    var isActive = true
    @ObservationIgnored weak var store: BrowserStore?
    @ObservationIgnored var downloadView: WKWebView?
    @ObservationIgnored private var progressObservation: NSKeyValueObservation?
    @ObservationIgnored private var scope: URL?
    @ObservationIgnored private var workingURL: URL?

    init(download: WKDownload, store: BrowserStore, spaceID: UUID, restoring id: UUID? = nil) {
        self.id = id ?? UUID()
        self.download = download
        self.store = store
        self.spaceID = spaceID
        super.init()
        if let old = store.session.downloads.first(where: { $0.id == self.id }) {
            name = old.name
            if let data = old.destinationBookmark {
                var stale = false
                if let url = try? URL(
                    resolvingBookmarkData: data, options: [.withSecurityScope], bookmarkDataIsStale: &stale)
                {
                    scope = url
                    _ = url.startAccessingSecurityScopedResource()
                }
            }
        } else {
            store.session.downloads.insert(
                BrowserDownloadRecord(
                    id: self.id, spaceID: spaceID, name: name,
                    source: download.originalRequest?.url), at: 0)
        }
        download.delegate = self
        progressObservation = download.progress.observe(\.completedUnitCount, options: [.new]) {
            [weak self] progress, _ in
            Task { @MainActor in
                self?.update {
                    $0.received = progress.completedUnitCount
                    $0.expected = progress.totalUnitCount
                }
            }
        }
        update {
            $0.status = .running
            $0.resumeData = nil
            $0.error = nil
            if let method = download.originalRequest?.httpMethod { $0.requestMethod = method }
        }
    }

    func download(
        _ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String,
        completionHandler: @escaping @MainActor @Sendable (URL?) -> Void
    ) {
        Task {
            guard isActive, let store else {
                completionHandler(nil)
                cancel()
                return
            }
            if !download.isUserInitiated,
                let url = download.originalRequest?.mainDocumentURL ?? download.originalRequest?.url,
                let origin = BrowserStore.siteOrigin(url)
            {
                let decision = store.permission(.automaticDownloads, origin: origin, spaceID: spaceID)
                if decision == .deny {
                    completionHandler(nil)
                    cancel()
                    return
                }
                if decision == .ask {
                    let alert = NSAlert()
                    alert.messageText = "Allow automatic downloads?"
                    alert.informativeText = origin
                    alert.addButton(withTitle: "Don't Allow")
                    alert.addButton(withTitle: "Allow")
                    let allowed = await BrowserDialogs.ask(alert, in: store.window) == .alertSecondButtonReturn
                    store.setPermission(
                        .automaticDownloads, origin: origin, spaceID: spaceID, decision: allowed ? .allow : .deny)
                    guard allowed, isActive else {
                        completionHandler(nil)
                        cancel()
                        return
                    }
                }
            }
            name = BrowserDownloadFile.safeFilename(suggestedFilename)
            let risk = BrowserDownloadFile.risks(
                suggested: suggestedFilename, sanitized: name, mime: response.mimeType,
                initiated: download.isUserInitiated)
            update {
                $0.name = self.name
                $0.mimeType = response.mimeType
                $0.risk = risk
            }
            if !risk.isEmpty {
                let alert = NSAlert()
                alert.messageText = "Check this download"
                alert.informativeText = risk.joined(separator: "\n")
                alert.addButton(withTitle: "Cancel")
                alert.addButton(withTitle: "Download")
                guard await BrowserDialogs.ask(alert, in: store.window) == .alertSecondButtonReturn, isActive else {
                    completionHandler(nil)
                    cancel()
                    return
                }
            }
            guard store.session.spaces.contains(where: { $0.id == spaceID }) else {
                completionHandler(nil)
                cancel()
                return
            }
            var destination = store.session.downloads.first { $0.id == id }?.destination
            if destination == nil && !store.preferences.downloadsAskEveryTime {
                var stale = false
                let bookmark = store.session.spaces.first { $0.id == spaceID }?.downloadDirectory
                let directory =
                    bookmark.flatMap {
                        try? URL(resolvingBookmarkData: $0, options: [.withSecurityScope], bookmarkDataIsStale: &stale)
                    }
                    ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                if let directory {
                    scope = directory
                    _ = directory.startAccessingSecurityScopedResource()
                    var target = directory.appendingPathComponent(name)
                    let ext = target.pathExtension
                    let stem = target.deletingPathExtension().lastPathComponent
                    var suffix = 1
                    while FileManager.default.fileExists(atPath: target.path) {
                        target = directory.appendingPathComponent(
                            stem + " (\(suffix))" + (ext.isEmpty ? "" : "." + ext))
                        suffix += 1
                    }
                    destination = target
                }
            }
            if destination == nil {
                let panel = NSSavePanel()
                panel.nameFieldStringValue = name
                panel.canCreateDirectories = true
                panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                let result: NSApplication.ModalResponse
                if let window = store.window {
                    result = await withCheckedContinuation { continuation in
                        panel.beginSheetModal(for: window) { continuation.resume(returning: $0) }
                    }
                } else {
                    result = panel.runModal()
                }
                guard result == .OK, isActive else {
                    completionHandler(nil)
                    cancel()
                    return
                }
                destination = panel.url
            }
            guard let target = destination else {
                completionHandler(nil)
                cancel()
                return
            }
            let directory = target.deletingLastPathComponent()
            if scope == nil {
                scope = directory
                _ = directory.startAccessingSecurityScopedResource()
            }
            let temporary = directory.appendingPathComponent(".Crest-download-\(id.uuidString)")
            workingURL = temporary
            let bookmark = try? directory.bookmarkData(
                options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            update {
                $0.destination = target
                $0.destinationBookmark = bookmark
                $0.status = .running
            }
            completionHandler(temporary)
        }
    }

    func download(
        _ download: WKDownload, didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @MainActor @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        Task {
            let result = await BrowserAuthentication.answer(challenge, in: store?.window)
            guard isActive else {
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }
            completionHandler(result.0, result.1)
        }
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let store, let record = store.session.downloads.first(where: { $0.id == id }),
            let destination = record.destination
        else {
            finish(.failed, error: "No destination was saved.")
            return
        }
        // A resumed WebKit task already knows its temporary path; resumeData owns that path.
        let temporary =
            workingURL
            ?? destination.deletingLastPathComponent().appendingPathComponent(".Crest-download-\(id.uuidString)")
        do {
            let metadata = "0083;\(String(Int(Date().timeIntervalSince1970), radix: 16));Crest;\(id.uuidString)"
            let result = metadata.withCString { ptr in
                setxattr(temporary.path, "com.apple.quarantine", ptr, strlen(ptr), 0, 0)
            }
            guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            if FileManager.default.fileExists(atPath: destination.path) {
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
            } else {
                try FileManager.default.moveItem(at: temporary, to: destination)
            }
            finish(.completed)
        } catch { finish(.failed, error: error.localizedDescription) }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        update {
            $0.resumeData = resumeData
            $0.status = resumeData == nil ? .failed : .paused
            $0.error = error.localizedDescription
        }
        release()
    }

    func pause() async {
        guard isActive else { return }
        let data: Data? = await withCheckedContinuation { continuation in
            download.cancel { continuation.resume(returning: $0) }
        }
        update {
            $0.resumeData = data
            $0.status = data == nil ? .failed : .paused
            $0.error = data == nil ? "This server did not provide resumable data." : nil
        }
        release()
    }

    func cancel() {
        download.cancel { _ in }
        finish(.cancelled)
        if let workingURL { try? FileManager.default.removeItem(at: workingURL) }
    }

    private func finish(_ status: BrowserDownloadRecord.Status, error: String? = nil) {
        update {
            $0.status = status
            $0.error = error
            if status == .completed || status == .cancelled { $0.resumeData = nil }
        }
        release()
    }

    private func release() {
        isActive = false
        progressObservation = nil
        scope?.stopAccessingSecurityScopedResource()
        scope = nil
        store?.downloads.removeValue(forKey: ObjectIdentifier(download))
        store?.runtimeRevision &+= 1
        downloadView = nil
        store?.changed()
    }

    private func update(_ apply: (inout BrowserDownloadRecord) -> Void) {
        guard let store, let index = store.session.downloads.firstIndex(where: { $0.id == id }) else { return }
        apply(&store.session.downloads[index])
        store.changed()
    }

}
