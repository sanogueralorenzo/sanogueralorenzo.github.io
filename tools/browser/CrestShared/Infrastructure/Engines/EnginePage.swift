import Foundation
import Security

/// The platform's direct path to one page's engine, whichever engine hosts
/// it: going back and forward, reloading, zooming, finding text and keeping
/// the page's history; capturing, exporting and inspecting its document; and
/// carrying Crest's site decisions to it. None of it changes browser state;
/// what it causes, such as a committed navigation, reaches the core as the
/// engine's events.
@MainActor
final class EnginePage: BrowserFindExecuting {
    // MARK: - Variables

    /// The core's page this one is.
    let id: UUID
    let pages: any EnginePages
    /// The engine the page's saved history belongs to, which a restore must
    /// match, and the version it is tagged with, which a restore must also
    /// match on an engine that reads back only its own version's history.
    private let historyFamily: BrowserEngineImplementation.Family
    private let historyVersion: @MainActor () -> String?
    /// The panels the engine's inspector starts on when asked to.
    private let inspectorPanels: Set<InspectorPanel>
    /// What waits for the engine: the latest find's count, and each capture
    /// and export by its identity.
    var findCompletion: (@MainActor (BrowserFindResult) -> Void)?
    var captures: [UUID: @MainActor (Data?) -> Void] = [:]
    var exports: [UUID: CheckedContinuation<Data, any Error>] = [:]
    /// What an agent's scripts and input wait for, by their identities.
    var agentWaits = EnginePageAgentWaits()
    /// The page's requested multiplier, retained across document and view
    /// replacement because an engine can reset its renderer's zoom then.
    private var requestedZoom: CGFloat?
    /// True once the page's owner let it go.
    private(set) var closed = false

    // MARK: - Initializers

    /// The direct path to page `id` over `pages`, whose saved history belongs
    /// to `historyFamily` at the version `historyVersion` names, and whose
    /// inspector starts on `inspectorPanels`.
    init(
        id: UUID, pages: any EnginePages, historyFamily: BrowserEngineImplementation.Family,
        historyVersion: @escaping @MainActor () -> String?, inspectorPanels: Set<InspectorPanel>
    ) {
        self.id = id
        self.pages = pages
        self.historyFamily = historyFamily
        self.historyVersion = historyVersion
        self.inspectorPanels = inspectorPanels
        pages.attach(self)
    }

    /// The page's owner let it go: what still waits for the engine ends
    /// empty-handed, and nothing more waits.
    func close() {
        guard !closed else { return }
        closed = true
        findCompletion = nil
        let waiting = captures
        captures = [:]
        for completion in waiting.values { completion(nil) }
        let exporting = exports
        exports = [:]
        for export in exporting.values { export.resume(throwing: BrowserPageExportError.pageUnavailable) }
        agentWaits.end()
    }

    // MARK: - Actions - Navigation

    func reload(bypassingCache: Bool = false) {
        pages.request(ReloadPage(pageID: id, bypassesCache: bypassingCache))
    }

    func stop() {
        pages.request(StopLoading(pageID: id))
    }

    /// Shows the page at `factor` of its normal size.
    func zoom(to factor: CGFloat) {
        guard !closed else { return }
        requestedZoom = factor
        pages.request(ZoomPage(pageID: id, factor: Double(factor)))
    }

    func restoreRequestedZoom() {
        guard !closed, let requestedZoom else { return }
        pages.request(ZoomPage(pageID: id, factor: Double(requestedZoom)))
    }

    // MARK: - Actions - History

    /// The page's history as the engine keeps it, to restore later on the same
    /// engine; nil when it has none, as before its engine starts.
    func savedHistory() -> Data? {
        guard pages.isReady, let version = historyVersion(),
            let state = pages.request(SaveInteractionState(pageID: id)).state
        else { return nil }
        return BrowserEngineInteractionState(engine: historyFamily, version: version, payload: state).encoded()
    }

    /// Restores history `savedHistory()` kept, in place of the page's first
    /// load of `url`; false when it belongs to another engine, or to another
    /// version of one that reads back only its own, or the engine refused it.
    func restoreHistory(_ saved: Data, expecting url: URL) -> Bool {
        guard let version = historyVersion(),
            let payload = BrowserEngineInteractionState.payload(saved, engine: historyFamily, version: version)
        else { return false }
        return pages.request(RestoreInteractionState(pageID: id, state: payload, expectedURL: url.absoluteString))
    }

    // MARK: - Actions - Find

    /// Finds `query` in the page. A new find replaces the one waiting for its
    /// count.
    func performFind(
        _ query: String, configuration: BrowserFindConfiguration,
        completion: @escaping @MainActor (BrowserFindResult) -> Void
    ) {
        findCompletion = nil
        guard
            pages.request(
                FindInPage(
                    pageID: id, query: query, backwards: configuration.backwards,
                    caseSensitive: configuration.caseSensitive))
        else {
            completion(.notFound)
            return
        }
        findCompletion = completion
    }

    // MARK: - Actions - Documents

    /// Captures what the page's view shows, all of it or `area` in view points
    /// from its top left, `width` points wide or at its own size, and hands
    /// `completion` a PNG, or nil when the view shows nothing. The engine is
    /// asked at once, so the capture shows the view as it is now.
    func capture(
        area: CGRect? = nil, width: CGFloat? = nil, completion: @escaping @MainActor (Data?) -> Void
    ) {
        let captureID = UUID()
        let pageArea = area.flatMap { $0.isEmpty ? nil : $0 }.map {
            PageArea(x: $0.minX, y: $0.minY, width: $0.width, height: $0.height)
        }
        guard !closed,
            pages.request(CapturePage(pageID: id, captureID: captureID, area: pageArea, width: width ?? 0))
        else {
            completion(nil)
            return
        }
        captures[captureID] = completion
    }

    /// The page's document as `format`, a full-page image `width` points wide
    /// or at its own width. Throws when the engine makes no such document, or
    /// the page navigated, closed or lost its renderer first.
    func export(_ format: PageExportFormat, width: CGFloat? = nil) async throws -> Data {
        let exportID = UUID()
        return try await withCheckedThrowingContinuation { continuation in
            guard !closed,
                pages.request(ExportPage(pageID: id, exportID: exportID, format: format, width: width ?? 0))
            else {
                continuation.resume(throwing: BrowserPageExportError.pageUnavailable)
                return
            }
            exports[exportID] = continuation
        }
    }

    /// The trust the page's current document was verified with, rebuilt from
    /// the engine's certificates with an SSL policy for `host`, for the
    /// certificate sheet; nil when the document came over no verified TLS.
    func serverTrust(host: String?) -> SecTrust? {
        guard pages.isReady, !closed else { return nil }
        let chain = pages.request(PageCertificates(pageID: id)).certificates
        guard !chain.isEmpty else { return nil }
        let certificates = chain.compactMap { SecCertificateCreateWithData(nil, $0 as CFData) }
        guard certificates.count == chain.count else { return nil }
        var trust: SecTrust?
        let policy = SecPolicyCreateSSL(true, host as CFString?)
        guard SecTrustCreateWithCertificates(certificates as CFArray, policy, &trust) == errSecSuccess else {
            return nil
        }
        return trust
    }

    // MARK: - Actions - Inspector

    /// Opens the engine's inspector on the page, on `panel` when the engine
    /// starts there; false when the page cannot be inspected.
    func openInspector(on panel: InspectorPanel? = nil) -> Bool {
        pages.request(OpenInspector(pageID: id, panel: panel))
    }

    /// Closes the page's inspector, docked or in a window of its own.
    func closeInspector() -> Bool {
        pages.request(CloseInspector(pageID: id))
    }

    /// Whether an inspector is open on the page.
    var isInspected: Bool {
        guard pages.isReady, !closed else { return false }
        return pages.request(PageInspected(pageID: id))
    }

    /// Whether an inspector opened on `panel` starts there, rather than
    /// wherever it last was.
    func inspectorStarts(on panel: InspectorPanel) -> Bool {
        inspectorPanels.contains(panel)
    }

    // MARK: - Actions - Sites

    /// Carries Crest's decision for `permission` on the page's site to the
    /// engine: true allows, false blocks, nil leaves the engine's default.
    /// False when the engine does not enforce it, and Crest's own bridges do.
    @discardableResult
    func setSitePermission(_ permission: SitePermission, allowed: Bool?) -> Bool {
        pages.request(SetSitePermission(pageID: id, permission: permission, allowed: allowed))
    }

    /// Ends capture from `permission`'s devices after Crest withdrew the
    /// grant that allowed it.
    func stopCapture(_ permission: SitePermission) {
        pages.request(StopMediaCapture(pageID: id, permission: permission))
    }

    /// Opens the popups the engine's blocker held back; false when it kept
    /// none.
    func showBlockedPopups() -> Bool {
        pages.request(ShowBlockedPopups(pageID: id))
    }

    /// The person's answer to a bar the engine raised; false when there is no
    /// such bar.
    func answerInfoBar(_ barID: Int, with answer: InfoBarAnswer) -> Bool {
        pages.request(AnswerInfoBar(pageID: id, infoBarID: barID, answer: answer))
    }

    /// Asks an engine that fetches the page's icon to fetch it again.
    func refreshIcon() {
        pages.request(RefreshPageIcon(pageID: id))
    }

    // MARK: - Actions - Screen sharing

    /// The person's answer to the engine's offer of tabs to share, `shareID`:
    /// the tab whose page is `tabPageID` for `.tab`, with its sound when
    /// `audio`. False when the request already ended, or the tab can no
    /// longer be shared.
    @discardableResult
    func chooseShareSource(
        _ shareID: UUID, choice: ShareSourceChoice, tabPageID: UUID? = nil, audio: Bool = false
    ) -> Bool {
        pages.request(
            ChooseShareSource(pageID: id, shareID: shareID, choice: choice, tabPageID: tabPageID, audio: audio))
    }

    /// Stops every tab sharing the page takes part in. False when it takes
    /// part in none.
    @discardableResult
    func stopTabSharing() -> Bool {
        pages.request(StopTabSharing(pageID: id))
    }

    // MARK: - Actions - Notifications

    /// Tells the document that posted the notification `notificationID` what
    /// became of it; false when the engine no longer has it.
    @discardableResult
    func answerWebNotification(_ notificationID: String, with answer: WebNotificationAnswer) -> Bool {
        pages.request(AnswerWebNotification(pageID: id, notificationID: notificationID, answer: answer))
    }

    // MARK: - Actions - Media

    /// What media the page runs now, as far as the engine knows.
    var mediaActivity: PageMediaActivity {
        guard pages.isReady, !closed else { return [] }
        return pages.request(PageMedia(pageID: id)).activity
    }

    /// Moves the video the page plays into Picture in Picture; false when it
    /// has none to move.
    func enterPictureInPicture() -> Bool {
        pages.request(EnterPictureInPicture(pageID: id))
    }

    /// Moves the page into window `windowID`, keeping its history and
    /// renderer, before the window shows it.
    func move(to windowID: UUID) -> Bool {
        pages.request(MovePageToWindow(pageID: id, windowID: windowID))
    }

    // MARK: - Actions - Presentations

    /// Hears what the engine finished for the page.
    func receive(_ presentation: EnginePresentation) {
        presentation.deliver(to: self)
    }
}

extension InspectorPanel {
    /// The engine's panel for Crest's developer panel.
    init(_ panel: BrowserDeveloperPanel) {
        switch panel {
        case .console: self = .console
        case .elements: self = .elements
        case .network: self = .network
        }
    }
}
