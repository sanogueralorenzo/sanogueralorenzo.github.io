import Combine
import Foundation
import WebKit

/// The files WebKit's pages download, run as the engine's own downloads the
/// core records. Each one reports its progress to the core and asks the core
/// where its file goes, with the platform's facts about the file, which the
/// core judges before it asks the person anything. What stays here is the
/// file handling: the file is staged in Crest's own folder and moved,
/// quarantined, to the place the core settled once WebKit finishes. A download
/// no person started passes the site's automatic-download choice first, which
/// the core answers or asks the person about; one it refuses waits for the
/// person's retry, which replays its request under the same name.
@MainActor
final class WebKitDownloads: NSObject {
    // MARK: - Types

    /// One download, from the page handing it over until the core clears it.
    @MainActor
    private final class Transfer {
        let id = UUID()
        let profileID: UUID
        let pageID: UUID
        weak var page: WebKitEnginePage?
        let startedAt = Date.now
        /// The request a retry replays, when WebKit can replay it.
        let replay: URLRequest?
        /// Where the file came from, which its quarantine records.
        let sourceURL: URL?
        /// The site its automatic-download choice belongs to.
        let origin: SiteOrigin?
        /// The Space whose choices answer for it, kept from its start, since
        /// a page opened only for the download goes away before WebKit asks
        /// where the file goes.
        let spaceID: UUID?
        let isUserInitiated: Bool
        var isApprovedRetry = false
        var filename: String
        var download: WKDownload?
        var progress: AnyCancellable?
        var received: Int64 = 0
        var total: Int64 = 0
        var isPaused = false
        /// The core's question about where the file goes, while it waits.
        var destinationPrompt: UUID?
        var staging: URL?
        var destination: URL?
        var isCanceling = false
        var hasEnded = false

        /// The engine's name for the download, which the core keeps it by.
        var engineID: String { id.uuidString }

        init(
            profileID: UUID, page: WebKitEnginePage, replay: URLRequest?, sourceURL: URL?, origin: SiteOrigin?,
            spaceID: UUID?, isUserInitiated: Bool, filename: String
        ) {
            self.profileID = profileID
            pageID = page.id
            self.page = page
            self.replay = replay
            self.sourceURL = sourceURL
            self.origin = origin
            self.spaceID = spaceID
            self.isUserInitiated = isUserInitiated
            self.filename = filename
        }
    }

    /// Where one page's site has had its one automatic download while its
    /// choice is Ask.
    private struct AutomaticScope: Hashable {
        let pageID: UUID
        let origin: SiteOrigin
    }

    // MARK: - Variables

    private unowned let binding: WebKitEngineBinding
    private var transfers: [String: Transfer] = [:]
    private var byDownload: [ObjectIdentifier: Transfer] = [:]
    private var destinations: [UUID: CheckedContinuation<String?, Never>] = [:]
    private var automaticAllowances: [AutomaticScope: Bool] = [:]

    // MARK: - Initializers

    init(binding: WebKitEngineBinding) {
        self.binding = binding
        super.init()
    }

    // MARK: - Actions - Starting

    /// Runs a download `page`'s web view handed over. `isUserInitiated`
    /// counts it as the person's own when WebKit does not know it is.
    func start(_ download: WKDownload, from page: WebKitEnginePage, isUserInitiated: Bool) {
        guard byDownload[ObjectIdentifier(download)] == nil else { return }
        let request = download.originalRequest
        let transfer = Transfer(
            profileID: page.profileID, page: page,
            replay: request?.replayableDownloadRequest,
            sourceURL: request?.url, origin: Self.origin(of: download, in: page.webView),
            spaceID: binding.core?.state.pages[page.id]?.spaceID,
            isUserInitiated: download.isUserInitiated || isUserInitiated,
            filename: request?.url?.lastPathComponent.nilIfEmpty ?? "download")
        transfers[transfer.engineID] = transfer
        register(download, for: transfer)
        report(transfer, .preparing)
    }

    /// Starts a new automatic-download sequence for page `pageID`, once its
    /// document is replaced or the page goes away.
    func resetAutomaticSequence(of pageID: UUID) {
        automaticAllowances = automaticAllowances.filter { $0.key.pageID != pageID }
    }

    private func register(_ download: WKDownload, for transfer: Transfer) {
        transfer.download = download
        byDownload[ObjectIdentifier(download)] = transfer
        download.delegate = self
        let progress = download.progress
        transfer.progress = Publishers.CombineLatest3(
            progress.publisher(for: \.completedUnitCount, options: [.initial, .new]),
            progress.publisher(for: \.totalUnitCount, options: [.initial, .new]),
            progress.publisher(for: \.isPaused, options: [.initial, .new])
        )
        .receive(on: DispatchQueue.main)
        .removeDuplicates { $0 == $1 }
        .throttle(for: .milliseconds(100), scheduler: DispatchQueue.main, latest: true)
        .sink { [weak self, weak transfer] completed, total, isPaused in
            MainActor.assumeIsolated {
                guard let self, let transfer, transfer.download === download, transfer.destination != nil else {
                    return
                }
                transfer.received = completed
                transfer.total = total
                transfer.isPaused = isPaused
                self.report(transfer, .downloading)
            }
        }
    }

    // MARK: - Actions - Commands

    /// Hands the file's place the core settled to the download waiting on it.
    func settle(_ settlement: SettleDownloadDestination) {
        destinations.removeValue(forKey: settlement.promptID)?.resume(returning: settlement.path)
    }

    /// Stops a download the core cancelled.
    func cancel(_ engineID: String) {
        guard let transfer = transfers[engineID], !transfer.hasEnded else { return }
        transfer.isCanceling = true
        if let download = transfer.download {
            download.cancel { _ in }
        } else {
            end(transfer, .canceled)
        }
        if let prompt = transfer.destinationPrompt { destinations.removeValue(forKey: prompt)?.resume(returning: nil) }
    }

    /// Forgets a download the core cleared, stopping it first if it still runs.
    func remove(_ engineID: String) {
        cancel(engineID)
        transfers[engineID] = nil
    }

    /// Replays a blocked download the person retried, as their own, under the
    /// same name. One whose page or request is gone fails, telling the person
    /// how to get it again.
    func approve(_ engineID: String) {
        guard let transfer = transfers[engineID], !transfer.hasEnded, transfer.download == nil else { return }
        guard let request = transfer.replay, let webView = transfer.page?.webView else {
            end(transfer, .failed, detail: "Reload the original page, then try the download again.")
            return
        }
        transfer.isApprovedRetry = true
        webView.startDownload(using: request) { [weak self] download in
            guard let self, self.transfers[engineID] === transfer, !transfer.hasEnded, transfer.download == nil else {
                download.cancel { _ in }
                return
            }
            self.register(download, for: transfer)
            self.report(transfer, .preparing)
        }
    }

    // MARK: - Actions - Destination

    /// Where WebKit writes `download`'s file: the staging copy of the place
    /// the core settled, once the site's automatic-download choice and the
    /// core allow it. Nil stops the download.
    fileprivate func destination(
        for download: WKDownload, response: URLResponse, suggestedFilename: String
    ) async -> URL? {
        guard let transfer = byDownload[ObjectIdentifier(download)] else { return nil }
        guard await allowsAutomatically(transfer), transfer.download === download, !transfer.hasEnded else {
            block(transfer, download)
            return nil
        }
        let promptID = UUID()
        transfer.destinationPrompt = promptID
        let path: String? = await withCheckedContinuation { continuation in
            destinations[promptID] = continuation
            binding.report(
                EngineDownloadDestinationRequested(
                    promptID: promptID, download: snapshot(transfer, .preparing), suggestedFilename: suggestedFilename,
                    forcesPrompt: false,
                    facts: DownloadRiskFacts(suggestedFilename: suggestedFilename, mimeType: response.mimeType),
                    userInitiated: transfer.isUserInitiated,
                    sourceHost: (response.url ?? transfer.sourceURL)?.host()))
        }
        transfer.destinationPrompt = nil
        guard let path, !transfer.hasEnded, transfer.download === download else {
            // Nowhere to go: the person declined or cancelled it.
            if !transfer.hasEnded { transfer.isCanceling = true }
            return nil
        }
        let destination = URL(fileURLWithPath: path)
        do {
            let staging = try Self.stagingDirectory()
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            transfer.staging = BrowserDownloadTransfer.stagingURL(
                itemID: transfer.id, suggestedFilename: suggestedFilename, directory: staging)
        } catch {
            end(transfer, .failed, interruption: .fileAccess, detail: error.localizedDescription)
            return nil
        }
        transfer.destination = destination
        transfer.filename = destination.lastPathComponent
        report(transfer, .downloading)
        return transfer.staging
    }

    /// Whether the site may send this file without the person asking for it:
    /// the core's rule over the site's choice and the page's one automatic
    /// download, asking the person through the core when the rule says so.
    /// A page that is gone can no longer ask, so only a saved choice lets
    /// its download go on.
    private func allowsAutomatically(_ transfer: Transfer) async -> Bool {
        let initiated = transfer.isUserInitiated || transfer.isApprovedRetry
        guard let origin = transfer.origin, let spaceID = transfer.spaceID else { return initiated }
        let saved =
            (try? binding.core?.query(
                SiteDecision(spaceID: spaceID, origin: origin, permission: .automaticDownloads, detail: nil)))?
            .decision ?? .denyPersistently
        let scope = AutomaticScope(pageID: transfer.pageID, origin: origin)
        let verdict = AutomaticDownloadCheck(
            userInitiated: transfer.isUserInitiated, userApprovedRetry: transfer.isApprovedRetry,
            savedDecision: saved, hasAllowedAutomaticDownload: automaticAllowances[scope] ?? false
        ).verdict
        automaticAllowances[scope] = verdict.hasAllowedAutomaticDownload
        return await verdict.action.settle(on: WebKitAutomaticDownloadRequest(page: transfer.page, origin: origin))
    }

    /// The site's choice refused `download`: it waits for the person's retry.
    private func block(_ transfer: Transfer, _ download: WKDownload) {
        guard transfer.download === download, !transfer.hasEnded else { return }
        forget(download, of: transfer)
        report(transfer, .blocked)
    }

    // MARK: - Actions - Ending

    fileprivate func finish(_ download: WKDownload) {
        guard let transfer = byDownload[ObjectIdentifier(download)] else { return }
        forget(download, of: transfer)
        guard let staging = transfer.staging, let destination = transfer.destination else {
            end(transfer, .failed, interruption: .fileAccess, detail: "The completed download has no destination.")
            return
        }
        do {
            let size = try? staging.resourceValues(forKeys: [.fileSizeKey]).fileSize.map(Int64.init)
            try BrowserDownloadTransfer.finish(
                from: staging, to: destination, quarantine: BrowserDownloadQuarantine(sourceURL: transfer.sourceURL))
            transfer.received = size ?? transfer.received
            transfer.total = max(transfer.total, transfer.received)
            end(transfer, .finished)
        } catch {
            end(transfer, .failed, interruption: .fileAccess, detail: error.localizedDescription)
        }
    }

    fileprivate func fail(_ download: WKDownload, error: any Error) {
        guard let transfer = byDownload[ObjectIdentifier(download)] else { return }
        forget(download, of: transfer)
        if transfer.isCanceling || (error as? URLError)?.code == .cancelled {
            end(transfer, .canceled)
        } else {
            end(transfer, .failed, interruption: Self.interruption(of: error), detail: error.localizedDescription)
        }
    }

    /// Lets go of the WebKit download `transfer` ran, which ended or stopped.
    private func forget(_ download: WKDownload, of transfer: Transfer) {
        byDownload[ObjectIdentifier(download)] = nil
        guard transfer.download === download else { return }
        transfer.download = nil
        transfer.progress = nil
    }

    /// Reports the download's end, once, and removes what it left staged.
    private func end(
        _ transfer: Transfer, _ state: EngineDownloadState, interruption: EngineDownloadInterruption? = nil,
        detail: String? = nil
    ) {
        guard !transfer.hasEnded else { return }
        transfer.hasEnded = true
        if state != .finished, let staging = transfer.staging { try? FileManager.default.removeItem(at: staging) }
        report(transfer, state, interruption: interruption, detail: detail)
    }

    // MARK: - Actions - Sign-in

    /// Answers a server's request for a user name and password on the
    /// download's behalf through its page, as the page's own loads are.
    fileprivate func answer(
        _ challenge: URLAuthenticationChallenge, for download: WKDownload,
        completionHandler: @escaping @MainActor @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        BrowserAuthenticationChallenge(challenge).handling.respond(
            on: WebKitSignInResponder(
                challenge: challenge, page: byDownload[ObjectIdentifier(download)]?.page, session: nil,
                completionHandler: completionHandler))
    }

    // MARK: - Actions - Reports

    private func report(
        _ transfer: Transfer, _ state: EngineDownloadState, interruption: EngineDownloadInterruption? = nil,
        detail: String? = nil
    ) {
        binding.report(
            EngineDownloadChanged(
                download: snapshot(transfer, state, interruption: interruption, detail: detail)))
    }

    /// The download as the core knows it. A blocked one names itself as what
    /// a retry approves.
    private func snapshot(
        _ transfer: Transfer, _ state: EngineDownloadState, interruption: EngineDownloadInterruption? = nil,
        detail: String? = nil
    ) -> EngineDownload {
        EngineDownload(
            downloadID: transfer.engineID, profileID: transfer.profileID, sourcePageID: transfer.pageID,
            filename: transfer.filename, path: transfer.destination?.path, received: transfer.received,
            total: transfer.total, startedAt: transfer.startedAt, restored: false, paused: transfer.isPaused,
            state: state, warning: nil, interruption: interruption, failureDetail: detail,
            approvalToken: state == .blocked ? transfer.engineID : "", canPause: false, canResume: false)
    }

    // MARK: - Actions - Facts

    /// The site a download belongs to: the page's own, including files its
    /// embedded frames or a CDN serve, so its site controls can change the
    /// rule; else the frame's, else the file's. The page is the document it
    /// shows: while a navigation that becomes a download is under way, the
    /// web view's URL is already the file's, after any redirect to its CDN.
    private static func origin(of download: WKDownload, in webView: WKWebView) -> SiteOrigin? {
        if let origin = webView.backForwardList.currentItem.flatMap({ SiteOrigin(url: $0.url) }) { return origin }
        let frameOrigin = SiteOrigin(download.originatingFrame.securityOrigin)
        if !frameOrigin.host.isEmpty { return frameOrigin }
        return download.originalRequest?.url.flatMap(SiteOrigin.init(url:))
    }

    /// Crest's own folder for files still downloading.
    private static func stagingDirectory() throws -> URL {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        .appendingPathComponent(ProductIdentity.storageDirectoryName, isDirectory: true)
        .appendingPathComponent("Download Staging", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// What stopped a download, as the core names it.
    private static func interruption(of error: any Error) -> EngineDownloadInterruption {
        let error = error as NSError
        if error.domain == NSURLErrorDomain {
            switch URLError.Code(rawValue: error.code) {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost, .cannotFindHost,
                .dnsLookupFailed, .secureConnectionFailed, .internationalRoamingOff, .dataNotAllowed:
                return .network
            case .badServerResponse, .resourceUnavailable, .fileDoesNotExist, .zeroByteResource:
                return .server
            case .cannotCreateFile, .cannotOpenFile, .cannotWriteToFile, .noPermissionsToReadFile:
                return .fileAccess
            default:
                return .other
            }
        }
        if error.domain == NSCocoaErrorDomain, error.code == NSFileWriteOutOfSpaceError { return .noSpace }
        if error.domain == NSPOSIXErrorDomain, error.code == Int(ENOSPC) { return .noSpace }
        return .other
    }
}

extension WebKitDownloads: WKDownloadDelegate {
    func download(
        _ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String
    ) async -> URL? {
        await destination(for: download, response: response, suggestedFilename: suggestedFilename)
    }

    func downloadDidFinish(_ download: WKDownload) {
        finish(download)
    }

    func download(_ download: WKDownload, didFailWithError error: any Error, resumeData: Data?) {
        fail(download, error: error)
    }

    func download(
        _ download: WKDownload, didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @MainActor @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        answer(challenge, for: download, completionHandler: completionHandler)
    }
}
