import AppKit
import Combine
import Foundation
import Observation
import PDFKit
import UniformTypeIdentifiers
import os

// MARK: - Types

enum BrowserDeveloperCaptureError: Error {
    case pageUnavailable
    case encodingFailed
}

/// Where the agent using a page's tab last acted on it, as the page shows the
/// person: the point in the page's CSS pixels, and whether it pressed there.
/// Each move is a new `revision`, so a second press at one point still shows.
struct BrowserAgentPointer: Equatable, Sendable {
    let point: PagePoint
    let presses: Bool
    let revision: Int
}

@Observable
@MainActor
final class BrowserPage: NSObject, BrowserMediaSessionCommandEndpoint {
    // MARK: - Static Variables

    @ObservationIgnored static let lifecycleSignposter = OSSignposter(
        subsystem: "com.pauldavis.crest",
        category: "WebKitLifecycle"
    )

    // MARK: - Variables

    /// The core's page, which `release(keepingState:)` ends.
    @ObservationIgnored let corePage: CorePage
    /// The engine's per-page adapter. Everything the page asks of its engine
    /// goes through it or through `pageEngine`. It changes when the core moves
    /// the page to another engine, and the page's card then shows the new
    /// engine's view.
    private(set) var engineAdapter: any BrowserPageEngineAdapter
    var pageEngine: any BrowserPageEngine { engineAdapter.engine }
    /// The page's direct path to its engine: going back, reloading, zooming,
    /// finding text and keeping its history.
    var enginePage: EnginePage { engineAdapter.enginePage }
    var pictureInPicture: (any BrowserPagePictureInPictureController)? { engineAdapter.pictureInPicture }
    var linkHover: BrowserLinkHoverController? { engineAdapter.linkHover }
    var linkDrag: BrowserLinkDragController? { engineAdapter.linkDrag }
    /// Restores the editing focus of the engine's view, once asked for.
    var focusRestoration: BrowserWebFocusRestorationController {
        if let focusRestorationStorage { return focusRestorationStorage }
        let controller = BrowserWebFocusRestorationController(webView: nativeView)
        engineAdapter.install(controller)
        focusRestorationStorage = controller
        return controller
    }
    @ObservationIgnored private var focusRestorationStorage: BrowserWebFocusRestorationController?
    /// What the page's engine is built with, which a new engine takes too.
    @ObservationIgnored private let mediaSessionStore: BrowserMediaSessionStore?
    @ObservationIgnored private let allowsCredentialAccess: Bool
    @ObservationIgnored private(set) var isPrivateBrowsing = false

    /// What the page shows as the core holds it: its address, title,
    /// loading, history, security, failure and media. Presentation that
    /// changes constantly, such as progress, find and zoom, stays here.
    var live: PageLiveState { corePage.live }
    var estimatedProgress = 0.0
    var isContentFullscreen: Bool {
        get { observed(\.isContentFullscreenStorage, as: \.isContentFullscreen) }
        set { publish(newValue, into: \.isContentFullscreenStorage, as: \.isContentFullscreen) }
    }
    @ObservationIgnored private var isContentFullscreenStorage = false
    var faviconData: Data?
    var themeColor: NSColor?
    /// Documents the page committed and finished, which reveal its surface.
    var committedNavigationCount = 0
    var completedNavigationCount = 0
    @ObservationIgnored var hasCommittedNavigationAwaitingCompletion = false
    var blockedPopupState = BrowserBlockedPopupPageState()
    var engineInfoBars: [BrowserEngineInfoBar] = []
    /// The engine's offer of tabs to share, while the person chooses.
    var shareSourceOffer: BrowserShareSourceOffer?
    /// Whether another page shares this one as a tab now.
    var isSharedAsTab = false
    /// Whether this page shares another tab now.
    var isSharingTab = false
    /// The pages of the tabs this page chose to share in the picker, while
    /// it shares any.
    var sharedTabPageIDs: Set<UUID> = []
    /// The bars the person hid until they come back to the page.
    var minimizedInfoBarIDs: Set<Int> = []
    /// The engine's bars the page shows now.
    var visibleEngineInfoBars: [BrowserEngineInfoBar] {
        engineInfoBars.filter { !minimizedInfoBarIDs.contains($0.id) }
    }
    var pendingServerTrustIdentity: BrowserServerTrustIdentity?
    /// Why the page's engine couldn't create it, which the page shows in
    /// place of its content.
    var webContentFailureMessage: String?
    var isFindPresented: Bool { findSession.isPresented }
    var findQuery: String { findSession.query }
    var findMatchState: BrowserFindMatchState { findSession.matchState }
    var findMatches: BrowserFindMatches? { findSession.matches }
    var findFocusRequest: Int { findSession.focusRequest }
    var findFocusesQueryField: Bool { findSession.focusesQueryField }
    var canFindAgain: Bool { findSession.canFindAgain }
    private(set) var pageZoom: CGFloat = BrowserDefaultPageZoomStore.defaultLevel
    let translation = BrowserPageTranslation()
    var readerModeState: BrowserReaderModeState { readerModeSession?.state ?? .unavailable }
    var isContentBlockingActive: Bool { engineAdapter.isContentBlockingActive }
    var developerPanel: BrowserDeveloperPanel?
    private(set) var isRegionCapturePresented = false
    /// Where the agent using the page's tab last acted, which the page shows
    /// as the agent's pointer while the agent uses the tab.
    private(set) var agentPointer: BrowserAgentPointer?
    /// The page's alert, confirm, prompt or leave-page question waiting on an
    /// answer while it shows, which an agent using the tab may read and, all
    /// but a leave-page question, answer.
    var scriptDialog: ScriptDialogAsked?
    private(set) var developerCaptureFeedback: String?
    private(set) var developerCaptureFeedbackRevision = 0
    var isCredentialAccessEnabled: Bool { credentialSession.isEnabled }
    var credentialFillRequest: BrowserCredentialFillRequest? { credentialState.fillRequest }
    var credentialSaveCandidate: BrowserCredentialSaveCandidate? { credentialState.saveCandidate }
    /// The pool that owns this page. Weak because the pool owns the page.
    @ObservationIgnored weak var host: BrowserPagePool?
    @ObservationIgnored var windowRouting: BrowserPageWindowRouting?

    /// True when web content opened this page through `window.open()`. WebKit
    /// drives such a page's history, so it neither restores nor archives any.
    @ObservationIgnored private(set) var wasOpenedAsPopup = false

    /// True from adoption until WebKit starts the popup's own navigation. WebKit
    /// drives an adopted popup, so nothing else may load it in that window —
    /// loading it here is what breaks `window.opener` and `document.write`.
    @ObservationIgnored var isAwaitingPopupNavigation = false

    @ObservationIgnored private var defaultPageZoom: CGFloat
    @ObservationIgnored private var hasTemporaryPageZoomOverride = false

    @ObservationIgnored let dialogPresenter: BrowserDialogPresenter
    /// The app's passkey access, refreshed when a secure page commits.
    @ObservationIgnored let passkeyAccess: BrowserPasskeyAccessController?
    @ObservationIgnored let fileUploadAccess = BrowserFileUploadAccess()
    @ObservationIgnored var downloadCenter: BrowserDownloadCenter
    /// Where the person started the download the page's engine reports next,
    /// when the engine saw it and the pointer may have left the page: the link
    /// WebKit's activation bridge saw them click. The core's word that the
    /// download began takes it.
    @ObservationIgnored var startedDownloadSource: BrowserDownloadFeedbackSource?
    let sitePermissionRequests = BrowserPagePermissionController()
    @ObservationIgnored let permissionCenter: BrowserSitePermissionCenter
    /// Carries Crest's site permission decisions to the engine as they change.
    @ObservationIgnored private(set) var sitePermissionSession: BrowserPageSitePermissionSession
    @ObservationIgnored let hostedNotificationCenter: (any BrowserHostedWebNotificationCentering)?
    /// The system notifications the page's documents posted that Crest shows.
    @ObservationIgnored var webNotificationIdentifiers: Set<String> = []
    /// Counts each time Crest takes the page's notifications down, so one
    /// still on its way to the system then never shows.
    @ObservationIgnored var webNotificationGeneration = 0
    @ObservationIgnored let recoverNotificationSystemAuthorization: @MainActor () async -> Void
    /// The system's consent the page asks before it sends the person's Allow
    /// to the core, whichever engine hosts it.
    @ObservationIgnored lazy var systemConsent: any BrowserSystemConsenting = BrowserSystemConsent(
        location: { [weak self] in await self?.systemAuthorizesLocation() ?? false },
        notifications: { [weak self] in await self?.authorizedForSystemNotifications(requestIfNeeded: true) ?? false })
    @ObservationIgnored let serverTrustOverrides: BrowserServerTrustOverrideStore
    @ObservationIgnored let spaceID: UUID
    @ObservationIgnored let profileID: UUID
    @ObservationIgnored let spaceName: String
    @ObservationIgnored let navigationDecider: BrowserNavigationDecider
    @ObservationIgnored let externalSchemeCoordinator: BrowserExternalSchemeCoordinator
    /// The URL Crest asked this page to load, as opposed to one web content
    /// asked for. Only an app-initiated load may reach a `file:` URL.
    @ObservationIgnored var appInitiatedURL: URL?
    @ObservationIgnored let openModifiedLink: (URLRequest, UUID, Bool) -> Void
    @ObservationIgnored let openPeek: (BrowserPeekRequest) -> Void
    @ObservationIgnored let handleLinkDrag: (BrowserPeekInteractionEvent) -> Void
    @ObservationIgnored var navigationContext: BrowserPageNavigationContext?
    @ObservationIgnored private let findSession = BrowserFindSession()
    var readerModeSession: BrowserReaderModeSession? { engineAdapter.readerModeSession }
    var faviconSession: BrowserFaviconSession? { engineAdapter.faviconSession }
    @ObservationIgnored var sharingPicker: NSSharingServicePicker?
    @ObservationIgnored private var printOperation: NSPrintOperation?
    @ObservationIgnored private var preparingPrint = false
    /// The link the pending web-content context menu is over. Read and cleared
    /// by this page's `BrowserDesktopWebViewMenuHost` conformance.
    @ObservationIgnored var linkContextCapture = BrowserLinkContextCapture()
    @ObservationIgnored var downloadSourceStore = BrowserDownloadSourceStore()
    @ObservationIgnored var splitLinkHost: BrowserSplitLinkHost
    @ObservationIgnored var linkDestinationHost: BrowserLinkDestinationHost
    @ObservationIgnored var mediaSessionCoordinator: BrowserMediaSessionPageCoordinator?
    @ObservationIgnored private(set) var userActivityHandler: (() -> Void)?
    /// Whether a window brought the page on screen and the person has not
    /// used it since, which the diagnostic log notes once they do.
    @ObservationIgnored var awaitsInputSincePresented = false
    @ObservationIgnored let credentialSession: BrowserCredentialSession
    var credentialState: BrowserCredentialPageState<BrowserCredentialSession.FillTarget> {
        credentialSession.state
    }
    @ObservationIgnored let httpAuthenticationSession: BrowserHTTPAuthenticationSession

    // Session-only presentation state belongs to the live page, including in splits.
    private var developerToolbarVisibilityOverride: Bool?
    var developerViewport: BrowserDeveloperViewport? {
        didSet { enginePage.zoom(to: renderedPageZoom) }
    }

    var renderedPageZoom: CGFloat { developerViewport == nil ? pageZoom : 1 }

    var isDeveloperModeEnabled: Bool {
        developerToolbarVisibilityOverride ?? (developerViewport != nil || isDeveloperModeAutomatic)
    }

    /// Whether this page's address turns the developer toolbar on by itself:
    /// a local development address, while the person keeps that preference on.
    var isDeveloperModeAutomatic: Bool {
        BrowserAppPreferenceStore.shared.automaticallyShowsDeveloperToolbar
            && live.displayURL?.isLocalDevelopmentAddress == true
    }

    /// The tab that owns this page's Media Session, read when the session
    /// reports rather than captured when it is built.
    var mediaSessionOwner: @MainActor () -> BrowserTabRuntimeAssignment? {
        { [weak self] in
            self?.navigationContext.map {
                BrowserTabRuntimeAssignment(
                    tabID: $0.tabID, spaceID: $0.spaceID, profileID: $0.spaceAssignment.profileID)
            }
        }
    }

    var mediaSessionFallbackTitle: @MainActor () -> String? {
        { [weak self] in
            guard let self else { return nil }
            let title = self.live.title
            return self.navigationContext?.mediaSessionOwnerTitle(observedPageTitle: title)
                ?? BrowserShownTitle.resolve(title)
        }
    }

    var siteThemeIconAccent: BrowserTabIconAccent? {
        guard let color = themeColor?.usingColorSpace(.sRGB), color.alphaComponent > 0 else {
            return nil
        }
        return BrowserTabIconAccent(
            red: Double(color.redComponent),
            green: Double(color.greenComponent),
            blue: Double(color.blueComponent)
        )
    }

    // MARK: - Initializers

    init(
        corePage: CorePage,
        engine engineAdapter: any BrowserPageEngineAdapter,
        dialogPresenter: BrowserDialogPresenter,
        downloadCenter: BrowserDownloadCenter,
        permissionCenter: BrowserSitePermissionCenter,
        hostedNotificationCenter:
            (any BrowserHostedWebNotificationCentering)? = nil,
        passkeyAccess: BrowserPasskeyAccessController? = nil,
        recoverNotificationSystemAuthorization:
            (@MainActor () async -> Void)? = nil,
        serverTrustOverrides: BrowserServerTrustOverrideStore = BrowserServerTrustOverrideStore(),
        mediaSessionStore: BrowserMediaSessionStore? = nil,
        spaceID: UUID,
        profileID: UUID,
        spaceName: String,
        allowsCredentialAccess: Bool = true,
        isCredentialAccessEnabled: Bool = true,
        defaultPageZoom: CGFloat = BrowserDefaultPageZoomStore.defaultLevel,
        loadHTTPAuthenticationCredential:
            @escaping BrowserHTTPAuthenticationSession.LoadCredential = { _ in nil },
        saveHTTPAuthenticationCredential:
            @escaping BrowserHTTPAuthenticationSession.SaveCredential = { _ in },
        openModifiedLink: @escaping (URLRequest, UUID, Bool) -> Void = { _, _, _ in },
        openPeek: @escaping (BrowserPeekRequest) -> Void = { _ in },
        handleLinkDrag: @escaping (BrowserPeekInteractionEvent) -> Void = { _ in },
        splitLinkHost: BrowserSplitLinkHost = .unavailable,
        linkDestinationHost: BrowserLinkDestinationHost = .unavailable,
        opensExternalURL: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) }
    ) {
        let pageInterval = Self.lifecycleSignposter.beginInterval("Initialize Browser Page")
        defer {
            Self.lifecycleSignposter.endInterval("Initialize Browser Page", pageInterval)
        }

        self.dialogPresenter = dialogPresenter
        self.downloadCenter = downloadCenter
        self.passkeyAccess = passkeyAccess
        self.permissionCenter = permissionCenter
        self.hostedNotificationCenter = hostedNotificationCenter
        self.recoverNotificationSystemAuthorization =
            recoverNotificationSystemAuthorization
            ?? {
                await dialogPresenter
                    .recoverNotificationSystemAuthorization()
            }
        self.serverTrustOverrides = serverTrustOverrides
        self.spaceID = spaceID
        self.profileID = profileID
        self.spaceName = spaceName
        self.corePage = corePage
        self.engineAdapter = engineAdapter
        self.mediaSessionStore = mediaSessionStore
        self.allowsCredentialAccess = allowsCredentialAccess
        sitePermissionSession = BrowserPageSitePermissionSession(
            page: engineAdapter.enginePage, permissionCenter: permissionCenter, spaceID: spaceID)
        let normalizedDefaultPageZoom = BrowserDefaultPageZoomStore.normalized(
            defaultPageZoom
        )
        self.defaultPageZoom = normalizedDefaultPageZoom
        pageZoom = normalizedDefaultPageZoom
        self.openModifiedLink = openModifiedLink
        self.openPeek = openPeek
        self.handleLinkDrag = handleLinkDrag
        self.splitLinkHost = splitLinkHost
        self.linkDestinationHost = linkDestinationHost
        let httpAuthenticationSession = BrowserHTTPAuthenticationSession(
            spaceID: spaceID,
            allowsCredentialSaving: allowsCredentialAccess
                && isCredentialAccessEnabled,
            loadCredential: loadHTTPAuthenticationCredential,
            saveCredential: saveHTTPAuthenticationCredential
        )
        self.httpAuthenticationSession = httpAuthenticationSession
        credentialSession = BrowserCredentialSession(
            spaceID: spaceID,
            core: downloadCenter.core,
            supportsAccess: allowsCredentialAccess,
            isEnabled: isCredentialAccessEnabled,
            httpAuthentication: httpAuthenticationSession
        )
        navigationDecider = BrowserNavigationDecider()
        // A popup whose destination belongs to another application is routed
        // into the same consent path an ordinary external-scheme navigation
        // takes.
        let externalSchemeCoordinator = BrowserExternalSchemeCoordinator(
            spaceID: spaceID,
            spaceName: spaceName,
            permissionCenter: permissionCenter,
            prompt: { origin, destinationURL, requestedSpaceName in
                await dialogPresenter.presentExternalApplicationPermission(
                    origin: origin,
                    destinationURL: destinationURL,
                    spaceName: requestedSpaceName
                )
            },
            opensExternalURL: opensExternalURL
        )
        self.externalSchemeCoordinator = externalSchemeCoordinator
        super.init()
        corePage.engineMoved = { [weak self] in self?.moveToNewEngine() }
        installEngine()
    }

    /// Wires the engine adapter into the page: the site decisions it carries,
    /// the Space's zoom, its delegates and bridges, its Media Session, and the
    /// content bridges an engine runs itself.
    private func installEngine() {
        sitePermissionSession.siteURL = { [weak self] in self?.pageEngine.currentURL ?? self?.live.documentURL }
        sitePermissionSession.siteDecisionDidChange = { [weak self] in self?.sitePermissionDidChange($0) }
        // The Space's default zoom; an engine that creates its page later
        // replays it then.
        enginePage.zoom(to: pageZoom)
        engineAdapter.attach(to: self, allowsCredentialAccess: allowsCredentialAccess)
        engineAdapter.setPrivateBrowsing(isPrivateBrowsing)
        if let mediaSessionStore {
            mediaSessionCoordinator = engineAdapter.makeMediaSessionCoordinator(for: self, store: mediaSessionStore)
        }
        if userActivityHandler != nil { engineAdapter.monitorUserActivity(for: self) }
        // An engine that runs Crest's content bridges itself receives them here;
        // the WebKit adapter installs its own through its user content controller.
        if allowsCredentialAccess, let scripting = pageEngine.contentScripting {
            _ = scripting.install(
                BrowserContentScript(
                    source: BrowserCredentialContentBridge.source,
                    handlerName: BrowserCredentialContentBridge.messageHandlerName,
                    mainFrameOnly: false
                )
            ) { [weak self] message in
                guard let self else { return }
                self.credentialSession.receive(
                    message.body, from: message.frame, topLevelURL: self.pageEngine.currentURL)
            }
        }
    }

    // MARK: - Actions - Navigation

    /// Records that web content opened this page and that WebKit still owes it a
    /// navigation. Only a page pool adopting a popup calls this.
    func markOpenedAsPopup() {
        wasOpenedAsPopup = true
        isAwaitingPopupNavigation = true
    }

    func load(_ url: URL) {
        load(URLRequest(url: url))
    }

    /// Loads `request` in the page as the app's own load, which only the app
    /// may make: the core's `LoadPage`, or a request web content made that
    /// the app replays. An address the person asked for goes through the
    /// core's `Navigate`, never here.
    func load(_ request: URLRequest) {
        // An engine that reports its own navigations prepares the page when it
        // says one started; until then the page only shows the load pending.
        if pageEngine.reportsNavigationState, request.url != nil {
            engineAdapter.reporter?.heading(to: request.url)
            webContentFailureMessage = nil
            pageEngine.load(request)
            return
        }
        appInitiatedURL = request.url
        prepareForNavigation(to: request.url)
        pageEngine.load(request)
    }

    /// The adapter's tagged, opaque history. Uncommitted pages return nil so
    /// an empty renderer cannot overwrite a useful archive.
    var interactionState: Data? {
        guard pageEngine.registration.supports(.interactionState) else { return nil }
        return enginePage.savedHistory()
    }

    /// Lets the adapter restore its own history instead of starting `url` afresh.
    /// Rejected state falls back to an ordinary load; an adapter that queues page
    /// creation also owns that fallback if restoration fails after attachment.
    @discardableResult
    func restoreInteractionState(_ state: Data, expecting url: URL) -> Bool {
        // WebKit owns an adopted popup's first navigation, and an adopted popup
        // has no archived state of its own to restore in the first place.
        guard pageEngine.registration.supports(.interactionState),
            !isAwaitingPopupNavigation, !wasOpenedAsPopup
        else { return false }
        appInitiatedURL = url
        prepareForNavigation(to: url)
        guard enginePage.restoreHistory(state, expecting: url) else {
            engineAdapter.reporter?.interrupted()
            return false
        }
        return true
    }

    func monitorUserActivity(_ handler: @escaping () -> Void) {
        userActivityHandler = handler
        engineAdapter.monitorUserActivity(for: self)
    }

    func styleVisitedLinks(history: [HistoryEntryState]) async {
        await engineAdapter.styleVisitedLinks(history: history)
    }

    func stopMonitoringUserActivity() {
        userActivityHandler = nil
    }

    /// Notes in the diagnostic log the person's first input after a window
    /// brought the page on screen, as the engine reports it.
    func awaitInputSincePresented() {
        awaitsInputSincePresented = true
    }

    /// Takes the tab's current context: its title, placement and icon.
    func updateNavigationContext(tab: BrowserPageTab) {
        let previousTitle = navigationContext?.title
        let shouldRefreshAutomaticIcon =
            tab.state.iconMode.followsPage
            && !tab.hasCurrentAutomaticFavicon
            && live.url != nil
            && !live.isLoading
        if faviconData != tab.displayFaviconData
            || navigationContext?.iconMode != tab.state.iconMode
            || navigationContext?.tabID != tab.id
        {
            faviconSession?.invalidate()
            faviconData = tab.displayFaviconData
        }
        navigationContext = BrowserPageNavigationContext(
            tab: tab.state,
            spaceID: spaceID,
            profileID: profileID
        )
        linkDrag?.contextDidChange()
        if previousTitle != navigationContext?.title {
            mediaSessionCoordinator?.ownerTitleDidChange()
        }
        if shouldRefreshAutomaticIcon {
            refreshFavicon()
        }
    }

    /// Ends the page: every page ends here, whether its tab closed, it was
    /// unloaded, its Space went, or a transient request let it go. The page's
    /// hosting comes down first, then the core hears the page is gone and asks
    /// its engine to close what it holds. `keepingState` says the owner kept
    /// what it needs to bring the page back.
    func release(keepingState: Bool) {
        tearDown()
        corePage.release(keepingState: keepingState)
    }

    /// Ends a page the core unloaded under memory pressure: its hosting comes
    /// down as on any release, but the core already closed what its engine
    /// held, so it hears nothing more.
    func unloaded() {
        tearDown()
        corePage.unloaded()
    }

    private func tearDown() {
        sitePermissionRequests.setPresentationAvailable(false)
        translation.reset()
        fileUploadAccess.invalidate()
        userActivityHandler = nil
        linkContextCapture.clear()
        tearDownEngine()
    }

    /// Takes down what the page's engine hosts for it, without telling the
    /// core, which ends the page or has already moved it.
    private func tearDownEngine() {
        faviconSession?.stop()
        readerModeSession?.invalidate()
        linkHover?.detach()
        linkDrag?.detach()
        focusRestorationStorage?.invalidate()
        focusRestorationStorage = nil
        mediaSessionCoordinator?.prepareForRemoval()
        pictureInPicture?.invalidate()
        sitePermissionSession.resetMediaGrants()
        webKitAdapter?.webKitPage.resetAutomaticDownloads()
        removeWebNotifications()
        engineAdapter.detach(from: self)
        mediaSessionCoordinator = nil
    }

    /// Hosts the page on the engine the core moved it to. The old engine's
    /// hosting comes down, the new engine's adapter and view take its place,
    /// and the page keeps its identity, so the tab, lease or window that
    /// holds it keeps it. What the old engine showed of the page, such as its
    /// bars, a find or a translation, goes with it.
    private func moveToNewEngine() {
        guard let hosted = corePage.movedHost(from: pageEngine.registration.kind) else { return }
        let adapter = hosted.makeDesktopAdapter()
        translation.reset()
        linkContextCapture.clear()
        findSession.dismiss(using: enginePage)
        tearDownEngine()
        engineAdapter = adapter
        sitePermissionSession = BrowserPageSitePermissionSession(
            page: adapter.enginePage, permissionCenter: permissionCenter, spaceID: spaceID)
        engineInfoBars = []
        shareSourceOffer = nil
        isRegionCapturePresented = false
        isSharedAsTab = false
        isSharingTab = false
        sharedTabPageIDs = []
        minimizedInfoBarIDs = []
        developerPanel = nil
        webContentFailureMessage = nil
        installEngine()
    }

    /// Whether the page belongs to a private window, which its engine takes
    /// on, now and whenever the page moves to another engine.
    func setPrivateBrowsing(_ isPrivate: Bool) {
        isPrivateBrowsing = isPrivate
        engineAdapter.setPrivateBrowsing(isPrivate)
    }

    /// Tries again to show a page its engine couldn't create.
    func retryAfterProcessFailure() {
        webContentFailureMessage = nil
        enginePage.reload(bypassingCache: false)
    }

    // MARK: - Actions - Find and developer tools

    func setDeveloperToolbarVisible(_ visible: Bool) {
        developerToolbarVisibilityOverride = visible
        if !visible { developerViewport = nil }
    }

    func presentFind() {
        findSession.present(hasLoadedPage: live.url != nil)
    }

    @discardableResult
    func showWebInspector() -> Bool {
        guard enginePage.isInspected else { return enginePage.openInspector() }
        // An inspector the engine refuses to close keeps its panel selected.
        guard enginePage.closeInspector() else { return false }
        developerPanel = nil
        return true
    }

    /// Closes the inspector showing `panel`, or opens one on it. An engine
    /// that cannot start on `panel` opens wherever it last was, and the page
    /// claims no panel it did not choose.
    func toggleDeveloperPanel(_ panel: BrowserDeveloperPanel) {
        let requested = InspectorPanel(panel)
        if developerPanel == panel, enginePage.isInspected {
            if enginePage.closeInspector() { developerPanel = nil } else { NSSound.beep() }
        } else if enginePage.openInspector(on: requested) {
            developerPanel = enginePage.inspectorStarts(on: requested) ? panel : nil
        } else {
            NSSound.beep()
        }
    }

    func beginRegionCapture() {
        guard live.url != nil else { return }
        isRegionCapturePresented = true
    }

    func cancelRegionCapture() {
        isRegionCapturePresented = false
    }

    func toggleRegionCapture() {
        if isRegionCapturePresented { cancelRegionCapture() } else { beginRegionCapture() }
    }

    func captureRegion(_ rect: CGRect) {
        guard isRegionCapturePresented else { return }
        isRegionCapturePresented = false
        Task { [weak self] in
            guard let self else { return }
            do {
                let png = await withCheckedContinuation { continuation in
                    enginePage.capture(area: rect) { continuation.resume(returning: $0) }
                }
                guard let image = png.flatMap(NSImage.init(data:)) else {
                    throw BrowserDeveloperCaptureError.pageUnavailable
                }
                guard Self.copyImageToPasteboard(image) else {
                    throw BrowserDeveloperCaptureError.encodingFailed
                }
                presentDeveloperCaptureFeedback("Capture Copied")
            } catch {
                presentDeveloperCaptureFeedback("Couldn’t Capture Page")
            }
        }
    }

    func copyFullPageCapture() {
        Task { [weak self] in
            guard let self else { return }
            do {
                let image = try await fullPageSnapshot()
                guard Self.copyImageToPasteboard(image) else {
                    throw BrowserDeveloperCaptureError.encodingFailed
                }
                presentDeveloperCaptureFeedback("Full Page Capture Copied")
            } catch {
                presentDeveloperCaptureFeedback("Couldn’t Capture Full Page")
            }
        }
    }

    func savePortraitCapture() {
        Task { [weak self] in
            guard let self, let window = nativeView.window else { return }
            do {
                let snapshot = try await fullPageSnapshot(snapshotWidth: 720)
                let portrait = Self.portraitImage(from: snapshot)
                guard let data = Self.pngData(from: portrait) else {
                    throw BrowserDeveloperCaptureError.encodingFailed
                }
                let panel = NSSavePanel()
                panel.allowedContentTypes = [.png]
                panel.canCreateDirectories = true
                panel.nameFieldStringValue = live.suggestedFilename(pathExtension: "png")
                panel.title = "Save Portrait Capture"
                panel.prompt = "Save"
                guard await panel.beginSheetModal(for: window) == .OK,
                    let destinationURL = panel.url
                else { return }
                try await Task.detached(priority: .userInitiated) {
                    try data.write(to: destinationURL, options: .atomic)
                }.value
                presentDeveloperCaptureFeedback("Portrait Capture Saved")
            } catch {
                presentDeveloperCaptureFeedback("Couldn’t Save Portrait Capture")
            }
        }
    }

    func dismissDeveloperCaptureFeedback() {
        developerCaptureFeedback = nil
    }

    private var findExecutor: any BrowserFindExecuting {
        enginePage
    }

    /// Closes find as the reader does, handing the keyboard back to the page
    /// they searched. The page's host takes focus as the bar leaves, unless
    /// something of Crest's, such as the address field, holds it by then.
    func dismissFind() {
        findSession.dismiss(using: findExecutor)
        focusRestoration.requestPageFocus()
    }

    func find(_ query: String, direction: BrowserFindDirection = .forward) {
        findSession.find(query, direction: direction, using: findExecutor)
    }

    func findAgain(_ direction: BrowserFindDirection) {
        findSession.findAgain(direction, hasLoadedPage: live.url != nil, using: findExecutor)
    }

    // MARK: - Actions - Zoom

    @discardableResult
    func zoomIn() -> Bool {
        guard developerViewport == nil else { return false }
        return setTemporaryPageZoom(pageZoom.pageZoomIncreased)
    }

    @discardableResult
    func zoomOut() -> Bool {
        guard developerViewport == nil else { return false }
        return setTemporaryPageZoom(pageZoom.pageZoomDecreased)
    }

    @discardableResult
    func resetZoom() -> Bool {
        guard developerViewport == nil else { return false }
        hasTemporaryPageZoomOverride = false
        return setPageZoom(defaultPageZoom)
    }

    /// Updates this page's global baseline without discarding a temporary zoom
    /// chosen through the page commands. A manually zoomed page rejoins the
    /// baseline when Reset is used, when recreation makes a new page, or when
    /// the newly selected default already equals its temporary value.
    @discardableResult
    func applyDefaultPageZoom(_ zoom: CGFloat) -> Bool {
        let normalized = BrowserDefaultPageZoomStore.normalized(zoom)
        defaultPageZoom = normalized
        if hasTemporaryPageZoomOverride {
            if pageZoom.matchesPageZoom(normalized) {
                hasTemporaryPageZoomOverride = false
            }
            return false
        }
        return setPageZoom(normalized)
    }

    // MARK: - Actions - Agents

    /// Moves the agent's pointer to `point`, pressing there when `presses`.
    func pointAgent(at point: PagePoint, presses: Bool) {
        agentPointer = BrowserAgentPointer(
            point: point, presses: presses, revision: (agentPointer?.revision ?? 0) &+ 1)
    }

    // MARK: - Actions - Reader and info bars

    func refreshReaderModeAvailability() async {
        await readerModeSession?.refreshAvailability()
    }

    func toggleReaderMode() {
        readerModeSession?.toggle()
    }

    func respond(to bar: BrowserEngineInfoBar, with response: BrowserEngineInfoBar.Response) {
        // The engine withdraws the bar itself once it has taken the answer.
        if !enginePage.answerInfoBar(bar.id, with: InfoBarAnswer(response)) {
            engineInfoBars.removeAll { $0.id == bar.id }
        }
    }

    /// Hides a bar that reports something lasting until the person comes back
    /// to the page.
    func minimize(_ bar: BrowserEngineInfoBar) {
        guard bar.isMinimizable else { return }
        minimizedInfoBarIDs.insert(bar.id)
    }

    /// The page left the screen: the bars the person hid show again when they
    /// come back to it.
    func restoreMinimizedInfoBars() {
        minimizedInfoBarIDs = []
    }

    // MARK: - Actions - Screen sharing

    /// The person's answer to the engine's offer of tabs to share. The page
    /// takes the offer down at once; the engine refuses the request when it
    /// cannot carry the answer out.
    func answer(_ offer: BrowserShareSourceOffer, with choice: BrowserShareSourceOffer.Choice) {
        guard shareSourceOffer?.id == offer.id else { return }
        shareSourceOffer = nil
        if let tabPageID = choice.tabPageID { sharedTabPageIDs.insert(tabPageID) }
        enginePage.chooseShareSource(
            offer.id, choice: choice.kind, tabPageID: choice.tabPageID, audio: choice.sharesAudio)
    }

    /// Stops every tab sharing the page takes part in, as the shared tab or
    /// as the page that shares one.
    func stopTabSharing() {
        enginePage.stopTabSharing()
    }

    // MARK: - Actions - Credentials

    func dismissCredentialFillRequest() {
        credentialState.dismissFillRequest()
    }

    func setCredentialAccessEnabled(_ isEnabled: Bool) {
        credentialSession.setEnabled(isEnabled)
    }

    func dismissCredentialSaveCandidate() {
        credentialState.dismissSaveCandidate()
    }

    func fillCredential(_ credential: BrowserCredential, for requestID: UUID) async throws {
        guard let evaluate = credentialEvaluator else { throw CredentialVaultError.credentialManagerDisabled }
        try await credentialSession.fill(credential, for: requestID, evaluate: evaluate)
    }

    func fillGeneratedPassword(_ password: String, for requestID: UUID) async throws {
        guard let evaluate = credentialEvaluator else { throw CredentialVaultError.credentialManagerDisabled }
        try await credentialSession.fillGeneratedPassword(password, for: requestID, evaluate: evaluate)
    }

    /// Fills go back through the channel the credential bridge came in on.
    private var credentialEvaluator: BrowserCredentialSession.Evaluate? {
        guard let scripting = pageEngine.contentScripting else { return engineAdapter.credentialEvaluator }
        return { body, arguments, frame in
            try await scripting.callAsyncJavaScript(body, arguments: arguments, in: frame)
        }
    }

    /// The document whole-page translation rewrites, on the engine the page
    /// is on now.
    var translationDocument: BrowserTranslationDocument? { engineAdapter.translationDocument }

    // MARK: - Actions - Sharing and export

    @discardableResult
    func copyPageLink() -> Bool {
        BrowserPageLinkClipboard.copy(live.documentURL)
    }

    func copyDeveloperPageLink() {
        if copyPageLink() {
            presentDeveloperCaptureFeedback("URL Copied")
        }
    }

    @discardableResult
    func copyPageLinkAsMarkdown() -> Bool {
        guard let url = live.documentURL else { return false }
        let label = live.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedLabel = label.isEmpty ? (url.host() ?? url.absoluteString) : label
        let escapedLabel =
            resolvedLabel
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "]", with: "\\]")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("[\(escapedLabel)](\(url.absoluteString))", forType: .string)
        return true
    }

    /// The whole page as an image `snapshotWidth` points wide, or as wide in
    /// points as the engine drew it on this screen.
    private func fullPageSnapshot(snapshotWidth: CGFloat? = nil) async throws -> NSImage {
        guard live.url != nil else { throw BrowserDeveloperCaptureError.pageUnavailable }
        let backingScale = nativeView.window?.backingScaleFactor ?? 1
        let data = try await enginePage.export(.png, width: snapshotWidth)
        guard let image = NSImage(data: data), let bitmap = image.representations.first,
            bitmap.pixelsWide > 0, bitmap.pixelsHigh > 0
        else { throw BrowserDeveloperCaptureError.pageUnavailable }
        // Engines draw in device pixels; AppKit composes the capture in points.
        let width = snapshotWidth ?? CGFloat(bitmap.pixelsWide) / backingScale
        image.size = NSSize(width: width, height: CGFloat(bitmap.pixelsHigh) * width / CGFloat(bitmap.pixelsWide))
        return image
    }

    private static func copyImageToPasteboard(_ image: NSImage) -> Bool {
        guard let data = pngData(from: image) else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setData(data, forType: .png)
    }

    private static func pngData(from image: NSImage) -> Data? {
        var proposedRect = CGRect(origin: .zero, size: image.size)
        guard
            let cgImage = image.cgImage(
                forProposedRect: &proposedRect,
                context: nil,
                hints: nil
            )
        else { return nil }
        let representation = NSBitmapImageRep(cgImage: cgImage)
        return representation.representation(using: .png, properties: [:])
    }

    private static func portraitImage(from snapshot: NSImage) -> NSImage {
        let horizontalInset: CGFloat = 64
        let verticalInset: CGFloat = 72
        let canvasSize = CGSize(
            width: snapshot.size.width + horizontalInset * 2,
            height: snapshot.size.height + verticalInset * 2
        )
        let imageRect = CGRect(
            x: horizontalInset,
            y: verticalInset,
            width: snapshot.size.width,
            height: snapshot.size.height
        )

        return NSImage(size: canvasSize, flipped: false) { canvasRect in
            let gradient = NSGradient(colors: [
                NSColor(calibratedRed: 0.16, green: 0.20, blue: 0.34, alpha: 1),
                NSColor(calibratedRed: 0.48, green: 0.25, blue: 0.52, alpha: 1),
                NSColor(calibratedRed: 0.14, green: 0.54, blue: 0.62, alpha: 1),
            ])
            gradient?.draw(in: canvasRect, angle: -35)

            let context = NSGraphicsContext.current
            context?.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = .black.withAlphaComponent(0.38)
            shadow.shadowBlurRadius = 30
            shadow.shadowOffset = CGSize(width: 0, height: -14)
            shadow.set()
            NSColor.black.withAlphaComponent(0.18).setFill()
            NSBezierPath(
                roundedRect: imageRect.insetBy(dx: -2, dy: -2),
                xRadius: 14,
                yRadius: 14
            ).fill()
            context?.restoreGraphicsState()

            context?.saveGraphicsState()
            NSBezierPath(
                roundedRect: imageRect,
                xRadius: 12,
                yRadius: 12
            ).addClip()
            snapshot.draw(in: imageRect)
            context?.restoreGraphicsState()
            return true
        }
    }

    private func presentDeveloperCaptureFeedback(_ message: String) {
        developerCaptureFeedback = message
        developerCaptureFeedbackRevision &+= 1
    }

    func sharePage() {
        guard let url = live.documentURL else { return }
        let picker = NSSharingServicePicker(items: [url])
        picker.delegate = self
        sharingPicker = picker
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard let self, self.nativeView.window != nil, self.sharingPicker === picker else { return }
            let anchor = NSRect(
                x: self.nativeView.bounds.maxX - 1,
                y: self.nativeView.bounds.maxY - 1,
                width: 1,
                height: 1
            )
            picker.show(relativeTo: anchor, of: self.nativeView, preferredEdge: .minY)
        }
    }

    func printPage() {
        guard !preparingPrint, printOperation == nil, live.url != nil, let window = nativeView.window else { return }
        let printInfo = NSPrintInfo.shared.copy() as? NSPrintInfo ?? NSPrintInfo.shared
        let title = live.title
        let jobTitle = title.isEmpty ? live.documentURL?.host() ?? ProductIdentity.name : title
        preparingPrint = true
        Task { [weak self, weak window] in
            guard let self else { return }
            defer { preparingPrint = false }
            guard let window else { return }
            do {
                let operation = try await printOperation(with: printInfo)
                guard nativeView.window === window, window.isVisible else { return }
                operation.jobTitle = jobTitle
                printOperation = operation
                operation.runModal(
                    for: window, delegate: self,
                    didRun: #selector(printOperationDidRun(_:success:contextInfo:)), contextInfo: nil)
            } catch {
                guard window.isVisible else { return }
                Self.postFailureNotice("The page couldn’t be printed.", error: error)
            }
        }
    }

    /// The engine's own print operation for its view, or one over the PDF
    /// the engine exports.
    private func printOperation(with info: NSPrintInfo) async throws -> NSPrintOperation {
        if let operation = (pageEngine as? any BrowserPrintingPageEngine)?.printOperation(with: info) {
            return operation
        }
        guard let document = PDFDocument(data: try await pdfData()),
            let operation = document.printOperation(for: info, scalingMode: .pageScaleToFit, autoRotate: true)
        else {
            throw BrowserPageExportError.renderingFailed("The page could not be prepared for printing.")
        }
        return operation
    }

    func pdfData() async throws -> Data {
        guard live.url != nil else { throw BrowserPageExportError.pageUnavailable }
        return try await enginePage.export(.pdf)
    }

    func exportPDF() {
        guard let window = nativeView.window, live.url != nil else { return }
        let suggestedFilename = live.suggestedFilename(pathExtension: "pdf")
        Task { [weak self, weak window] in
            guard let self, let window else { return }
            do {
                let data = try await pdfData()
                let panel = NSSavePanel()
                panel.allowedContentTypes = [.pdf]
                panel.canCreateDirectories = true
                panel.nameFieldStringValue = suggestedFilename
                panel.title = "Export Page as PDF"
                panel.prompt = "Export"
                guard await panel.beginSheetModal(for: window) == .OK,
                    let destinationURL = panel.url
                else { return }
                try await Task.detached(priority: .userInitiated) {
                    try data.write(to: destinationURL, options: .atomic)
                }.value
            } catch {
                presentPDFExportError(error, in: window)
            }
        }
    }

    /// The page's document and resources, in the archive its engine keeps.
    func webArchiveData() async throws -> Data {
        guard live.url != nil else { throw BrowserPageExportError.pageUnavailable }
        return try await enginePage.export(pageEngine.registration.archiveFormat.exportFormat)
    }

    func exportWebArchive() {
        guard let window = nativeView.window, live.url != nil else { return }
        let format = pageEngine.registration.archiveFormat
        let suggestedFilename = live.suggestedFilename(pathExtension: format.pathExtension)
        Task { [weak self, weak window] in
            guard let self, let window else { return }
            do {
                let data = try await webArchiveData()
                let panel = NSSavePanel()
                panel.allowedContentTypes = [format.contentType]
                panel.canCreateDirectories = true
                panel.nameFieldStringValue = suggestedFilename
                panel.title = "Save Page as Web Archive"
                panel.prompt = "Save"
                guard await panel.beginSheetModal(for: window) == .OK,
                    let destinationURL = panel.url
                else { return }
                try await Task.detached(priority: .userInitiated) {
                    try data.write(to: destinationURL, options: .atomic)
                }.value
            } catch {
                presentWebArchiveExportError(error, in: window)
            }
        }
    }

    @objc private func printOperationDidRun(
        _ operation: NSPrintOperation,
        success: Bool,
        contextInfo: UnsafeMutableRawPointer?
    ) {
        if printOperation === operation {
            printOperation = nil
        }
    }

    // MARK: - Actions - Zoom state

    private func setTemporaryPageZoom(_ zoom: CGFloat) -> Bool {
        let changed = setPageZoom(zoom)
        hasTemporaryPageZoomOverride = !pageZoom.matchesPageZoom(defaultPageZoom)
        return changed
    }

    private func setPageZoom(_ zoom: CGFloat) -> Bool {
        guard zoom != pageZoom else {
            return false
        }
        pageZoom = zoom
        enginePage.zoom(to: renderedPageZoom)
        return true
    }

    // MARK: - Actions - Navigation state

    /// Readies the page for a navigation of its document to `url`, which the
    /// app asked for or the engine accepted: what belonged to the document it
    /// leaves goes, and the page shows it heading to `url`.
    func prepareForNavigation(to url: URL?) {
        // Same-document navigation never commits a replacement document.
        // Cancel the current pull here; suspend new pulls only when WebKit
        // actually starts provisional navigation.
        linkDrag?.cancel()
        isRegionCapturePresented = false
        sitePermissionSession.resetMediaGrants()
        sitePermissionRequests.cancelAll()
        translation.reset()
        readerModeSession?.invalidate()
        pictureInPicture?.invalidate()
        linkHover?.beginNavigation()
        focusRestoration.invalidate()
        mediaSessionCoordinator?.prepareForNavigation()
        beginBlockedPopupNavigation()
        synchronizePopupPermission(for: url)
        faviconSession?.invalidate()
        engineAdapter.reporter?.heading(to: url)
        // A capture describes one document's DOM. A right-click whose menu
        // never opened — a page that cancelled the event to draw its own —
        // must not survive into the next document.
        linkContextCapture.clear()
    }

    // MARK: - Actions - Engine observations

    /// Takes what the engine observed. Each event says what follows from it.
    func receive(_ event: any BrowserPageEngineEvent) {
        event.apply(to: self)
    }

    // MARK: - Actions - Site permissions

    /// Tells the page about a change to one of its site's permissions, after
    /// the engine applied it: the popup preference, the notifications the
    /// page shows and the bridges an engine runs inside the page follow the
    /// new decision.
    private func sitePermissionDidChange(_ permission: SitePermission) {
        if permission == .popups { synchronizePopupPermission() }
        if permission == .notifications { removeWebNotificationsNoLongerShown() }
        engineAdapter.sitePermissionDidChange(permission, on: self)
    }

    // MARK: - Actions - History availability

    /// Brings the engine's supplemental history up to date and tells the core
    /// what the page shows. An engine that reports its own navigation state
    /// already told it.
    func refreshNavigationState() {
        guard !pageEngine.reportsNavigationState else { return }
        synchronizeNavigationHistory()
        engineAdapter.reporter?.stateChanged()
    }

    /// The reporter that tells the core what the page's engine shows.
    var navigationReporter: EnginePageReporter? { engineAdapter.reporter }

    // MARK: - Actions - Failure notices

    private func presentPDFExportError(_ error: Error, in window: NSWindow) {
        Self.postFailureNotice("The page couldn’t be exported.", error: error)
    }

    private func presentWebArchiveExportError(_ error: Error, in window: NSWindow) {
        Self.postFailureNotice("The page couldn’t be saved as a web archive.", error: error)
    }

    /// A failed export or print needs nothing from the person, so it is a
    /// notice rather than an alert.
    private static func postFailureNotice(_ summary: String, error: Error) {
        BrowserNoticeCenter.shared.post(
            BrowserNotice(
                message: "\(summary) \(error.localizedDescription)",
                systemImage: "exclamationmark.triangle"))
    }

    // MARK: - Actions - Title and favicon

    func refreshFavicon() {
        guard navigationContext?.iconMode.followsPage == true, pageEngine.currentURL != nil else { return }
        if let faviconSession {
            faviconSession.refresh()
        } else {
            enginePage.refreshIcon()
        }
    }

    /// WebKit fetches the icon on demand; an engine that reports its own icon
    /// has already published it.
    func pullFavicon() async -> Data? {
        if let faviconSession { return await faviconSession.pull() }
        return faviconData
    }
}

extension BrowserPage: BrowserStoreFirstObservable {}
