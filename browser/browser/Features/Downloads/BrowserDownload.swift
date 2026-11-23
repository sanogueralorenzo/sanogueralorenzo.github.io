import AppKit
import Darwin
import Observation
import WebKit

@MainActor @Observable
final class BrowserDownload: NSObject, WKDownloadDelegate, Identifiable {
    let id: UUID
    let requestID: UUID
    let download: WKDownload
    let spaceID: UUID
    var name = "Download"
    var isActive = true
    private let windowID: UUID?
    @ObservationIgnored private weak var owner: BrowserSessionOwner?
    private var window: NSWindow? { owner?.downloadWindow(preferred: windowID) }
    @ObservationIgnored var downloadView: WKWebView?
    @ObservationIgnored private var progressObservation: NSKeyValueObservation?
    @ObservationIgnored private var scope: URL?
    @ObservationIgnored private var workingURL: URL?
    @ObservationIgnored private var pauseTask: Task<Void, Never>?

    init(
        download: WKDownload, owner: BrowserSessionOwner, spaceID: UUID, windowID: UUID?,
        restoring id: UUID?, requestID: UUID
    ) {
        self.id = id ?? UUID()
        self.requestID = requestID
        self.download = download
        self.owner = owner
        self.windowID = windowID
        self.spaceID = spaceID
        super.init()
        if let old = owner.session.downloads.first(where: { $0.id == self.id }) {
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
            owner.session.downloads.insert(
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
            guard isActive, let owner else {
                completionHandler(nil)
                cancel()
                return
            }
            if !download.isUserInitiated,
                let url = download.originalRequest?.mainDocumentURL ?? download.originalRequest?.url,
                let origin = BrowserStore.siteOrigin(url)
            {
                let decision = owner.permission(.automaticDownloads, origin: origin, spaceID: spaceID)
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
                    let allowed = await BrowserDialogs.ask(alert, in: window) == .alertSecondButtonReturn
                    owner.setPermission(
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
                guard await BrowserDialogs.ask(alert, in: window) == .alertSecondButtonReturn, isActive else {
                    completionHandler(nil)
                    cancel()
                    return
                }
            }
            guard owner.session.spaces.contains(where: { $0.id == spaceID }) else {
                completionHandler(nil)
                cancel()
                return
            }
            let record = owner.session.downloads.first { $0.id == id }
            var destination = record?.destination
            var replacementIdentity = record?.replacementIdentity
            if destination == nil && !owner.session.preferences.downloadsAskEveryTime {
                var stale = false
                let bookmark = owner.session.spaces.first { $0.id == spaceID }?.downloadDirectory
                let directory =
                    bookmark.flatMap {
                        try? URL(resolvingBookmarkData: $0, options: [.withSecurityScope], bookmarkDataIsStale: &stale)
                    }
                    ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                if let directory {
                    scope = directory
                    _ = directory.startAccessingSecurityScopedResource()
                    destination = directory.appendingPathComponent(name)
                }
            }
            if destination == nil {
                let panel = NSSavePanel()
                panel.nameFieldStringValue = name
                panel.canCreateDirectories = true
                panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                let result: NSApplication.ModalResponse
                if let window {
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
                replacementIdentity = destination.flatMap { BrowserDownloadFile.replacementIdentity(at: $0) }
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
            let temporary = directory.appendingPathComponent(".Browser-download-\(id.uuidString)")
            workingURL = temporary
            let bookmark = try? directory.bookmarkData(
                options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            update {
                $0.destination = target
                $0.destinationBookmark = bookmark
                $0.replacementIdentity = replacementIdentity
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
            let result = await BrowserAuthentication.answer(challenge, in: window)
            guard isActive else {
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }
            completionHandler(result.0, result.1)
        }
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard isActive else { return }
        guard let owner, let record = owner.session.downloads.first(where: { $0.id == id }),
            let destination = record.destination
        else {
            finish(.failed, error: "No destination was saved.")
            return
        }
        // WebKit resume data carries the original temporary path.
        let temporary =
            workingURL
            ?? destination.deletingLastPathComponent().appendingPathComponent(".Browser-download-\(id.uuidString)")
        do {
            let metadata = "0083;\(String(Int(Date().timeIntervalSince1970), radix: 16));Browser;\(id.uuidString)"
            let result = metadata.withCString { ptr in
                setxattr(temporary.path, "com.apple.quarantine", ptr, strlen(ptr), 0, 0)
            }
            guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            let published = try BrowserDownloadFile.publish(
                temporary, to: destination, replacing: record.replacementIdentity)
            update {
                $0.destination = published
                $0.name = published.lastPathComponent
                $0.replacementIdentity = nil
            }
            finish(.completed)
        } catch { finish(.failed, error: error.localizedDescription) }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        guard isActive, pauseTask == nil else { return }
        update {
            $0.resumeData = resumeData
            $0.status = resumeData == nil ? .failed : .paused
            $0.error = error.localizedDescription
        }
        release()
    }

    func pause() async {
        guard isActive else { return }
        if let pauseTask {
            await pauseTask.value
            return
        }
        let task = Task { [self] in
            let data: Data? = await withCheckedContinuation { continuation in
                download.cancel { continuation.resume(returning: $0) }
            }
            guard isActive else { return }
            update {
                $0.resumeData = data
                $0.status = data == nil ? .failed : .paused
                $0.error = data == nil ? "This server did not provide resumable data." : nil
            }
            release()
        }
        pauseTask = task
        await task.value
        pauseTask = nil
    }

    func cancel() {
        guard isActive else { return }
        if let workingURL { try? FileManager.default.removeItem(at: workingURL) }
        finish(.cancelled)
        download.cancel { _ in }
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
        owner?.downloads.removeValue(forKey: ObjectIdentifier(download))
        owner?.runtimeRevision &+= 1
        downloadView = nil
        owner?.changed()
    }

    private func update(_ apply: (inout BrowserDownloadRecord) -> Void) {
        guard isActive, let owner, let index = owner.session.downloads.firstIndex(where: { $0.id == id }) else {
            return
        }
        apply(&owner.session.downloads[index])
        owner.changed()
    }

}
