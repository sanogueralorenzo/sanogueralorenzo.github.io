import Dispatch
import Observation
import UIKit
import UniformTypeIdentifiers
import WebKit

@Observable
@MainActor
final class MobileBrowserPage: NSObject, BrowserMediaSessionCommandEndpoint {
    /// The core's page, which `release(keepingState:)` ends.
    @ObservationIgnored let corePage: CorePage
    private(set) var tabID: UUID
    let spaceID: UUID
    let profileID: UUID
    /// What WebKit's binding built for the page, which it keeps while it
    /// lives.
    @ObservationIgnored let webKitPage: WebKitEnginePage
    /// The page's direct path to WebKit: going back, reloading, zooming,
    /// finding text and keeping its history.
    @ObservationIgnored let enginePage: EnginePage
    let webView: WKWebView
    var webKitView: WKWebView { webView }
    // iOS composes one engine. Naming its type here keeps the page port in
    // play everywhere it is used while removing the force-cast the history
    // accessor needed to reach a WebKit-only service.
    @ObservationIgnored let pageEngine: BrowserWebKitPageEngine

    /// The store that owns this page. Weak because the store owns the page.
    weak var host: MobileBrowserPageStore?

    /// True when web content opened this page through `window.open()`. WebKit
    /// drives such a page's history, so it neither restores nor archives any.
    var wasOpenedAsPopup = false

    /// True from adoption until WebKit starts the popup's own navigation. WebKit
    /// drives an adopted popup, so nothing else may load it in that window —
    /// loading it here is what breaks `window.opener` and `document.write`.
    var isAwaitingPopupNavigation = false

    /// What the page shows as the core holds it: its address, title,
    /// loading, history, security, failure and media. Presentation that
    /// changes constantly, such as progress, find and zoom, stays here.
    var live: PageLiveState { corePage.live }
    private(set) var estimatedProgress = 0.0
    private(set) var faviconData: Data?
    private(set) var themeColor: UIColor?
    /// The color WebKit draws behind the page, kept as it changes so the
    /// chrome around the page can take it up.
    private(set) var underPageColor: UIColor?
    /// The history swipe of the view showing this page, for a swipe that
    /// starts on the frame beside it.
    @ObservationIgnored weak var historySwipe: MobileHistorySwipe?
    /// Documents the page committed and finished, which reveal its surface.
    var committedNavigationCount = 0
    private(set) var completedNavigationCount = 0
    var blockedPopupState = BrowserBlockedPopupPageState()
    var pendingServerTrustIdentity: BrowserServerTrustIdentity?
    /// The document's address as WebKit last published it.
    @ObservationIgnored private var documentURL: URL?
    var navigationHistory: BrowserPageNavigationHistory {
        get { pageEngine.history }
        set { pageEngine.history = newValue }
    }
    var isFindPresented: Bool { findSession.isPresented }
    var findQuery: String { findSession.query }
    var findMatchState: BrowserFindMatchState { findSession.matchState }
    var findFocusRequest: Int { findSession.focusRequest }
    private(set) var pageZoom: CGFloat = BrowserDefaultPageZoomStore.defaultLevel
    let translation = BrowserPageTranslation()
    /// The document whole-page translation rewrites.
    var translationDocument: BrowserTranslationDocument? { BrowserTranslationDocument(webView: webView) }
    var readerModeState: BrowserReaderModeState { readerModeSession.state }
    var isContentBlockingActive: Bool { webKitPage.isContentBlockingActive }
    private(set) var isRequestingDesktopSite = false
    var hasActiveLinkActivationBridge: Bool { linkActivationMessageProxy != nil }

    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private let pullToRefreshControl = UIRefreshControl()
    @ObservationIgnored let linkDestinationHost: BrowserLinkDestinationHost
    @ObservationIgnored private let openModifiedLink: MobileBrowserPageStore.ModifiedLinkOpener
    @ObservationIgnored let downloadCenter: BrowserDownloadCenter
    let sitePermissionRequests = BrowserPagePermissionController()
    /// Carries Crest's site permission decisions to the page as they change.
    @ObservationIgnored lazy var sitePermissionSession: BrowserPageSitePermissionSession = {
        let session = BrowserPageSitePermissionSession(
            page: enginePage, permissionCenter: permissionCenter, spaceID: spaceID)
        session.siteURL = { [weak self] in self?.pageEngine.currentURL ?? self?.live.documentURL }
        session.siteDecisionDidChange = { [weak self] permission in
            if permission == .popups { self?.synchronizePopupPermission() }
        }
        return session
    }()
    @ObservationIgnored let permissionCenter: BrowserSitePermissionCenter
    @ObservationIgnored let serverTrustOverrides: BrowserServerTrustOverrideStore
    @ObservationIgnored let navigationDecider: BrowserNavigationDecider
    @ObservationIgnored let popupCoordinator: BrowserPopupCoordinator
    @ObservationIgnored let externalSchemeCoordinator: BrowserExternalSchemeCoordinator
    /// The URL Crest asked this page to load, as opposed to one web content
    /// asked for. Only an app-initiated load may reach a `file:` URL.
    @ObservationIgnored var appInitiatedURL: URL?
    @ObservationIgnored private(set) var appInitiatedNavigationCount = 0
    @ObservationIgnored var contextMenuPreviewCommit: (() -> Void)?
    @ObservationIgnored var navigationContext: BrowserPageNavigationContext?
    @ObservationIgnored var activeNavigation: WKNavigation?
    @ObservationIgnored let spaceName: String
    @ObservationIgnored private let findSession = BrowserFindSession()
    @ObservationIgnored lazy var readerModeSession = BrowserReaderModeSession(
        document: BrowserWebKitReaderModeDocument(webView: webView, translation: translation)
    )
    @ObservationIgnored lazy var faviconSession = BrowserFaviconSession(
        document: BrowserWebKitFaviconDocument(webView: webView, profileID: profileID),
        policy: .immediate,
        receive: { [weak self] data in
            self?.faviconData = data
            self?.reporter.foundIcon(data, at: self?.webView.url)
        }
    )
    /// Tells the core what the page shows and what its navigations and icon do.
    @ObservationIgnored lazy var reporter = EnginePageReporter(
        page: corePage,
        snapshot: { [weak self] pendingURL in
            self?.snapshot(pendingURL: pendingURL)
                ?? PageSnapshot(
                    url: nil, pendingURL: pendingURL, title: "", isLoading: false, security: PageSecurity.none,
                    media: [])
        },
        history: { [weak self] in self?.pageEngine.reportedHistory })
    /// The reporter that tells the core what the page's engine shows.
    var navigationReporter: EnginePageReporter? { reporter }
    @ObservationIgnored private var linkActivationMessageProxy: MobileLinkActivationScriptMessageProxy?
    @ObservationIgnored var downloadSourceStore = BrowserDownloadSourceStore()
    @ObservationIgnored private var geolocationMessageProxy: BrowserScriptMessageProxy?
    @ObservationIgnored private var blockedPopupMessageProxy: BrowserScriptMessageProxy?
    @ObservationIgnored private var mediaSessionMessageProxy: BrowserScriptMessageProxy?
    @ObservationIgnored var mediaSessionCoordinator: BrowserMediaSessionPageCoordinator?
    @ObservationIgnored var geolocationCoordinator: BrowserGeolocationCoordinator?
    /// The system's consent the page asks before it sends the person's Allow
    /// to the core. The page shows no web notifications.
    @ObservationIgnored lazy var systemConsent: any BrowserSystemConsenting = BrowserSystemConsent(
        location: { [weak self] in await self?.geolocationCoordinator?.systemAuthorizes() ?? false },
        notifications: { false })
    @ObservationIgnored let httpAuthenticationSession: BrowserHTTPAuthenticationSession

    /// False when this page shares the opener's `WKUserContentController`, which
    /// every popup does. Installing the same script message handler twice on it
    /// throws, and removing one would strip it from the opener.
    @ObservationIgnored private let ownsUserContentController: Bool
    @ObservationIgnored private var defaultPageZoom: CGFloat
    @ObservationIgnored private var hasTemporaryPageZoomOverride = false

    /// The page hosting what WebKit's binding built as `webKitPage`, for
    /// `tab` in `space`.
    init(
        corePage: CorePage,
        webKitPage: WebKitEnginePage,
        tab: BrowserPageTab,
        space: SpaceModel,
        downloadCenter: BrowserDownloadCenter = BrowserDownloadCenter(),
        permissionCenter: BrowserSitePermissionCenter = BrowserSitePermissionCenter(),
        geolocationService: any BrowserGeolocationServicing =
            BrowserGeolocationSystemService(),
        recoverGeolocationSystemAuthorization:
            BrowserGeolocationCoordinator.RecoverSystemAuthorization? = nil,
        serverTrustOverrides: BrowserServerTrustOverrideStore = BrowserServerTrustOverrideStore(),
        mediaSessionStore: BrowserMediaSessionStore? = nil,
        defaultPageZoom: CGFloat = BrowserDefaultPageZoomStore.defaultLevel,
        loadsInitialURL: Bool = true,
        linkDestinationHost: BrowserLinkDestinationHost = .unavailable,
        openModifiedLink: @escaping MobileBrowserPageStore.ModifiedLinkOpener = {
            _, _, _ in nil
        },
        opensExternalURL: @escaping (URL) -> Void = { UIApplication.shared.open($0) }
    ) {
        self.corePage = corePage
        tabID = tab.id
        spaceID = space.id
        profileID = space.profileID
        faviconData = tab.displayFaviconData
        self.downloadCenter = downloadCenter
        self.permissionCenter = permissionCenter
        self.serverTrustOverrides = serverTrustOverrides
        self.linkDestinationHost = linkDestinationHost
        self.openModifiedLink = openModifiedLink
        spaceName = space.settings.name
        navigationContext = BrowserPageNavigationContext(
            tab: tab.state,
            spaceID: space.id,
            profileID: space.profileID
        )
        navigationDecider = BrowserNavigationDecider()
        // Built before the popup coordinator so a popup whose destination belongs
        // to another application can be routed into the same consent path an
        // ordinary external-scheme navigation takes.
        let externalSchemeCoordinator = BrowserExternalSchemeCoordinator(
            spaceID: space.id,
            spaceName: space.settings.name,
            permissionCenter: permissionCenter,
            prompt: { origin, destinationURL, requestedSpaceName in
                await MobileBrowserDialogPresenter.presentExternalApplicationPermission(
                    origin: origin,
                    destinationURL: destinationURL,
                    spaceName: requestedSpaceName
                )
            },
            opensExternalURL: opensExternalURL
        )
        self.externalSchemeCoordinator = externalSchemeCoordinator
        popupCoordinator = BrowserPopupCoordinator(
            handOffExternalScheme: { destinationURL, trigger, origin in
                externalSchemeCoordinator.handOff(
                    destinationURL: destinationURL,
                    trigger: trigger,
                    origin: origin
                )
            }
        )
        let normalizedDefaultPageZoom = BrowserDefaultPageZoomStore.normalized(defaultPageZoom)
        self.defaultPageZoom = normalizedDefaultPageZoom
        pageZoom = normalizedDefaultPageZoom
        let httpAuthenticationSession = BrowserHTTPAuthenticationSession()
        self.httpAuthenticationSession = httpAuthenticationSession

        // A popup's configuration is the one WebKit derived from its opener's,
        // which shares the opener's user content controller, so its scripts,
        // rule lists, and message handlers are already installed: adding them
        // again throws.
        ownsUserContentController = webKitPage.ownsUserContentController
        self.webKitPage = webKitPage
        enginePage = webKitPage.makeEnginePage()
        webView = webKitPage.webView
        pageEngine = webKitPage.engine
        if ownsUserContentController {
            linkActivationMessageProxy = MobileLinkActivationContentBridge.install(
                in: webView.configuration.userContentController
            )
        }

        super.init()
        if normalizedDefaultPageZoom != BrowserDefaultPageZoomStore.defaultLevel {
            webView.pageZoom = normalizedDefaultPageZoom
        }
        #if DEBUG
            // iOS ships no developer tooling of its own, so an inspectable
            // release web view would be attack surface and nothing else: any
            // trusted Mac could attach Safari's Web Inspector to a session.
            webView.isInspectable = true
        #endif
        webView.navigationDelegate = self
        webView.uiDelegate = self
        // Crest's own edge swipe steps the core's history
        // (`MobileHistorySwipe`); WebKit's would walk its own list.
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsLinkPreview = true
        if let mediaSessionStore {
            let coordinator = BrowserMediaSessionPageCoordinator(
                webView: webView,
                endpoint: self,
                store: mediaSessionStore,
                owner: { [weak self] in
                    guard let self else { return nil }
                    return BrowserTabRuntimeAssignment(
                        tabID: tabID,
                        spaceID: spaceID,
                        profileID: profileID
                    )
                },
                fallbackTitle: { [weak self] in
                    guard let self else { return nil }
                    return self.navigationContext?.mediaSessionOwnerTitle(
                        observedPageTitle: self.live.title
                    ) ?? BrowserShownTitle.resolve(self.live.title)
                }
            )
            mediaSessionCoordinator = coordinator
            if ownsUserContentController {
                mediaSessionMessageProxy =
                    BrowserMediaSessionContentBridge.install(
                        in: webView.configuration.userContentController
                    ) { [weak self] message in
                        self?.receiveMediaSessionMessage(message)
                    }
            }
        }
        linkActivationMessageProxy?.receive = { [weak self] message in
            self?.receiveLinkActivationMessage(message)
        }
        geolocationCoordinator = BrowserGeolocationCoordinator(
            webView: webView,
            permissionCenter: permissionCenter,
            service: geolocationService,
            spaceID: space.id,
            askSite: { [webKitPage] origin, topLevelOrigin in
                await webKitPage.ask(
                    PermissionQuestion(permission: .location, origin: origin, topLevelOrigin: topLevelOrigin))
            },
            recoverSystemAuthorization:
                recoverGeolocationSystemAuthorization
                ?? {
                    await MobileBrowserDialogPresenter
                        .recoverGeolocationSystemAuthorization()
                }
        )
        if ownsUserContentController {
            blockedPopupMessageProxy = BrowserBlockedPopupContentBridge.install(
                in: webView.configuration.userContentController
            ) { [weak self] message in
                self?.receiveBlockedPopupMessage(message)
            }
            geolocationMessageProxy = BrowserGeolocationContentBridge.install(
                in: webView.configuration.userContentController
            ) { [weak self] message in
                self?.receiveGeolocationMessage(message)
            }
        }
        installObservations()
        pullToRefreshControl.addTarget(
            self,
            action: #selector(refreshFromPull),
            for: .valueChanged
        )
        webView.scrollView.refreshControl = pullToRefreshControl
        // Observe permission changes from the start, not from the first grant.
        _ = sitePermissionSession

        // Last, so a page the core brings back restores into a page that
        // hears its navigations.
        webKitPage.attach(self)
        if loadsInitialURL, webView.url == nil, let url = tab.url {
            load(url)
        }
    }

    func load(_ url: URL) {
        load(URLRequest(url: url))
    }

    /// Loads `request` in the page as the app's own load, which only the app
    /// may make: the core's `LoadPage`, or a request web content made that
    /// the app replays. An address the person asked for goes through the
    /// core's `Navigate`, never here.
    func load(_ request: URLRequest) {
        if let url = request.url {
            prepareToLoad(url)
        } else {
            appInitiatedURL = nil
            prepareForNavigation(to: nil)
        }
        pageEngine.load(request)
    }

    /// The page shows itself heading to `url`, which only an app-initiated
    /// load may reach when it is a local file.
    func prepareToLoad(_ url: URL) {
        appInitiatedURL = url
        prepareForNavigation(to: url)
    }

    func mediaActivityMayHaveChanged() {
        refreshMediaActivity()
    }

    func historyMayHaveChanged() {
        reporter.reportHistoryAgain()
    }

    /// The page WebKit's binding built for this page, which hosts every page
    /// on iPhone and iPad.
    var webKitEnginePage: WebKitEnginePage { webKitPage }

    func routeModifiedLink(_ url: URL, selecting: Bool) {
        routeModifiedLink(URLRequest(url: url), selecting: selecting)
    }

    func routeModifiedLink(_ request: URLRequest, selecting: Bool) {
        guard let url = request.url,
            let registration = openModifiedLink(url, spaceID, selecting)
        else { return }
        host?.loadOpenedLink(registration, request: request, selecting: selecting, opener: corePage.id)
    }

    /// WebKit's own opaque per-view session state: the back/forward list and the
    /// scroll position of every entry in it.
    ///
    /// Nil until a document has committed. A web view that never loaded still
    /// answers `interactionState` with an empty session, and archiving that would
    /// replace a real state with one that restores nothing.
    var interactionState: Data? {
        enginePage.savedHistory()
    }

    /// Restores a previously archived `interactionState` instead of starting `url`
    /// afresh, and reports whether WebKit took it.
    ///
    /// WebKit performs the navigation itself once the state is installed, so this
    /// replaces `load(_:)` rather than preceding it. Invalid state is discarded
    /// silently by WebKit — no exception, nothing loaded — which is exactly the
    /// signal used here: a web view left without a current back/forward item did
    /// not restore, and the caller falls back to an ordinary load.
    @discardableResult
    func restoreInteractionState(_ state: Data, expecting url: URL) -> Bool {
        // WebKit owns an adopted popup's first navigation, and an adopted popup
        // has no archived state of its own to restore in the first place.
        guard !isAwaitingPopupNavigation, !wasOpenedAsPopup else { return false }
        appInitiatedURL = url
        prepareForNavigation(to: url)
        guard enginePage.restoreHistory(state, expecting: url) else {
            reporter.interrupted()
            return false
        }
        return true
    }

    /// Records that web content opened this page and that WebKit still owes it a
    /// navigation. Only a page store adopting a popup calls this.
    func markOpenedAsPopup() {
        wasOpenedAsPopup = true
        isAwaitingPopupNavigation = true
    }

    func styleVisitedLinks(history: [HistoryEntryState]) async {
        await BrowserVisitedLinkStyler.apply(history: history, to: webView)
    }

    func stopMonitoringUserActivity() {
    }

    func adopt(tabID: UUID, tab: BrowserPageTab) {
        self.tabID = tabID
        updateNavigationContext(tab: tab)
    }

    /// Takes the tab's current context: its title, placement and icon.
    func updateNavigationContext(tab: BrowserPageTab) {
        let previousTitle = navigationContext?.title
        let shouldRefreshAutomaticIcon =
            tab.state.iconMode.followsPage
            && !tab.hasCurrentAutomaticFavicon
            && webView.url != nil
            && !webView.isLoading
        if faviconData != tab.displayFaviconData
            || navigationContext?.iconMode != tab.state.iconMode
            || navigationContext?.tabID != tab.id
        {
            faviconSession.invalidate()
            faviconData = tab.displayFaviconData
        }
        navigationContext = BrowserPageNavigationContext(
            tab: tab.state,
            spaceID: spaceID,
            profileID: profileID
        )
        if previousTitle != navigationContext?.title {
            mediaSessionCoordinator?.ownerTitleDidChange()
        }
        if shouldRefreshAutomaticIcon {
            refreshFavicon()
        }
    }

    /// Ends the page: every page ends here, whether its tab closed, it was
    /// unloaded, its Space went, or a transient request let it go. The web view
    /// comes down first, then the core hears the page is gone. `keepingState`
    /// says the owner kept what it needs to bring the page back.
    func release(keepingState: Bool) {
        tearDownWebView()
        corePage.release(keepingState: keepingState)
    }

    /// Ends a page the core unloaded under memory pressure: its web view comes
    /// down as on any release, but the core already closed what its engine
    /// held, so it hears nothing more.
    func unloaded() {
        tearDownWebView()
        corePage.unloaded()
    }

    private func tearDownWebView() {
        enginePage.close()
        faviconSession.stop()
        sitePermissionSession.resetMediaGrants()
        sitePermissionRequests.setPresentationAvailable(false)
        translation.reset()
        readerModeSession.invalidate()
        mediaSessionCoordinator?.prepareForRemoval()
        webKitPage.resetAutomaticDownloads()
        webView.stopLoading()
        webView.removeFromSuperview()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        for observation in observations {
            observation.invalidate()
        }
        observations.removeAll()
        removeGeolocationRequests()
        guard ownsUserContentController else {
            linkActivationMessageProxy = nil
            geolocationMessageProxy = nil
            blockedPopupMessageProxy = nil
            mediaSessionMessageProxy = nil
            mediaSessionCoordinator = nil
            geolocationCoordinator = nil
            return
        }

        if linkActivationMessageProxy != nil {
            webView.configuration.userContentController
                .removeScriptMessageHandler(
                    forName: MobileLinkActivationContentBridge.messageHandlerName,
                    contentWorld: MobileLinkActivationContentBridge.contentWorld
                )
        }
        linkActivationMessageProxy?.receive = { _ in }
        linkActivationMessageProxy = nil
        if geolocationMessageProxy != nil {
            webView.configuration.userContentController
                .removeScriptMessageHandler(
                    forName: BrowserGeolocationContentBridge.messageHandlerName,
                    contentWorld: BrowserGeolocationContentBridge.contentWorld
                )
        }
        geolocationMessageProxy = nil
        if blockedPopupMessageProxy != nil {
            webView.configuration.userContentController
                .removeScriptMessageHandler(
                    forName: BrowserBlockedPopupContentBridge.messageHandlerName,
                    contentWorld: BrowserBlockedPopupContentBridge.contentWorld
                )
        }
        blockedPopupMessageProxy = nil
        if mediaSessionMessageProxy != nil {
            webView.configuration.userContentController
                .removeScriptMessageHandler(
                    forName: BrowserMediaSessionContentBridge.messageHandlerName,
                    contentWorld: BrowserMediaSessionContentBridge.contentWorld
                )
        }
        mediaSessionMessageProxy = nil
        mediaSessionCoordinator = nil
        geolocationCoordinator = nil
    }

    func reloadOrStop() {
        performReload(.standard)
    }

    func togglePreferredContentMode() {
        isRequestingDesktopSite.toggle()
        webView.configuration.defaultWebpagePreferences.preferredContentMode =
            isRequestingDesktopSite ? .desktop : .recommended
        guard webView.url != nil else { return }
        webView.reloadFromOrigin()
    }

    func applyContentBlocking(
        policy: ContentBlockingPolicy,
        activation: BrowserContentBlockingActivation = .onNextNavigation
    ) {
        webKitPage.applyContentBlocking(
            policy: policy,
            reloadsImmediately: activation == .immediately && webView.url != nil
        )
    }

    func presentFind() {
        findSession.present(hasLoadedPage: webView.url != nil)
    }

    func dismissFind() {
        findSession.dismiss(using: enginePage)
    }

    func find(_ query: String, direction: BrowserFindDirection = .forward) {
        findSession.find(query, direction: direction, using: enginePage)
    }

    @discardableResult
    func zoomIn() -> Bool {
        setTemporaryPageZoom(pageZoom.pageZoomIncreased)
    }

    @discardableResult
    func zoomOut() -> Bool {
        setTemporaryPageZoom(pageZoom.pageZoomDecreased)
    }

    @discardableResult
    func resetZoom() -> Bool {
        hasTemporaryPageZoomOverride = false
        return setPageZoom(defaultPageZoom)
    }

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

    func refreshReaderModeAvailability() async {
        await readerModeSession.refreshAvailability()
    }

    func toggleReaderMode() {
        readerModeSession.toggle()
    }

    @discardableResult
    func copyPageLink() -> Bool {
        BrowserPageLinkClipboard.copy(live.documentURL)
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
        UIPasteboard.general.string = "[\(escapedLabel)](\(url.absoluteString))"
        return true
    }

    func printPage() {
        guard webView.url != nil else { return }
        let controller = UIPrintInteractionController.shared
        let printInfo = UIPrintInfo(dictionary: nil)
        printInfo.outputType = .general
        printInfo.jobName = live.title.isEmpty ? live.documentURL?.host() ?? ProductIdentity.name : live.title
        controller.printInfo = printInfo
        controller.printFormatter = webView.viewPrintFormatter()

        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, self.webView.window != nil else { return }
            if UIDevice.current.userInterfaceIdiom == .pad {
                controller.present(
                    from: CGRect(x: self.webView.bounds.maxX - 1, y: 1, width: 1, height: 1),
                    in: self.webView,
                    animated: true,
                    completionHandler: nil
                )
            } else {
                controller.present(animated: true, completionHandler: nil)
            }
        }
    }

    func pdfData() async throws -> Data {
        guard webView.url != nil else { throw BrowserPageExportError.pageUnavailable }
        return try await webView.pdf(configuration: WKPDFConfiguration())
    }

    func exportPDF(to destination: MobileBrowserFileExportDestination) {
        guard webView.url != nil else { return }
        let suggestedFilename = live.suggestedFilename(pathExtension: "pdf")
        Task { [weak self] in
            guard let self else { return }
            do {
                let data = try await pdfData()
                try await MobileBrowserDialogPresenter.exportDocument(
                    data,
                    filename: suggestedFilename,
                    to: destination
                )
            } catch {
                MobileBrowserDialogPresenter.presentError(
                    title: "The page couldn’t be exported.",
                    message: error.localizedDescription
                )
            }
        }
    }

    func webArchiveData() async throws -> Data {
        guard webView.url != nil else { throw BrowserPageExportError.pageUnavailable }
        return try await withCheckedThrowingContinuation { continuation in
            webView.createWebArchiveData { result in
                continuation.resume(with: result)
            }
        }
    }

    func exportWebArchive(to destination: MobileBrowserFileExportDestination) {
        guard webView.url != nil else { return }
        let suggestedFilename = live.suggestedFilename(
            pathExtension: BrowserPageArchiveFormat.webArchive.pathExtension)
        Task { [weak self] in
            guard let self else { return }
            do {
                let data = try await webArchiveData()
                try await MobileBrowserDialogPresenter.exportDocument(
                    data,
                    filename: suggestedFilename,
                    to: destination
                )
            } catch {
                MobileBrowserDialogPresenter.presentError(
                    title: "The page couldn’t be saved as a web archive.",
                    message: error.localizedDescription
                )
            }
        }
    }

    private func installObservations() {
        observations = [
            webView.observe(\.url, options: [.initial, .new]) { [weak self] webView, _ in
                Task { @MainActor in
                    guard let self else { return }
                    if let url = webView.url {
                        self.translation.documentURLDidChange(from: self.documentURL, to: url)
                        self.documentURL = url
                        self.refreshNavigationState()
                        self.reportMoveWithinDocument(to: url)
                    }
                }
            },
            webView.observe(\.title, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor in
                    self?.mediaSessionCoordinator?.ownerTitleDidChange()
                    self?.refreshNavigationState()
                    self?.reporter.titleChanged()
                }
            },
            webView.observe(\.estimatedProgress, options: [.initial, .new]) { [weak self] webView, _ in
                Task { @MainActor in self?.estimatedProgress = webView.estimatedProgress }
            },
            webView.observe(\.isLoading, options: [.initial, .new]) { [weak self] webView, _ in
                Task { @MainActor in
                    self?.refreshNavigationState()
                    self?.refreshMediaActivity()
                    if !webView.isLoading {
                        self?.pullToRefreshControl.endRefreshing()
                    }
                }
            },
            webView.observe(\.hasOnlySecureContent, options: [.new]) { [weak self] _, _ in
                Task { @MainActor in self?.reporter.stateChanged() }
            },
            webView.observe(\.serverTrust, options: [.new]) { [weak self] _, _ in
                Task { @MainActor in self?.reporter.stateChanged() }
            },
            webView.observe(\.cameraCaptureState, options: [.new]) { [weak self] _, _ in
                Task { @MainActor in self?.refreshMediaActivity() }
            },
            webView.observe(\.microphoneCaptureState, options: [.new]) { [weak self] _, _ in
                Task { @MainActor in self?.refreshMediaActivity() }
            },
            webView.observe(\.themeColor, options: [.initial, .new]) { [weak self] webView, _ in
                Task { @MainActor in
                    let themeColor = webView.themeColor
                    self?.themeColor = themeColor
                    self?.reporter.themeChanged(self?.siteThemeIconAccent)
                    // A standards-provided theme color owns the browser's
                    // overscroll atmosphere. Nil restores WebKit's derived
                    // html/body background instead of inventing a Crest color.
                    self?.updateUnderPageBackground()
                }
            },
            webView.observe(\.underPageBackgroundColor, options: [.initial, .new]) { [weak self] webView, _ in
                Task { @MainActor in self?.underPageColor = webView.underPageBackgroundColor }
            },
            webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] webView, _ in
                Task { @MainActor in self?.refreshNavigationState() }
            },
            webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] webView, _ in
                Task { @MainActor in self?.refreshNavigationState() }
            },
        ]
    }

    /// WebKit tells its delegate nothing about a move within the document,
    /// such as `history.pushState` or a fragment. The address changing while
    /// nothing loads, neither a request Crest made nor a navigation WebKit
    /// started, is that move.
    private func reportMoveWithinDocument(to url: URL) {
        guard activeNavigation == nil, !webView.isLoading else { return }
        reporter.movedWithinDocument(to: url)
    }

    @objc private func refreshFromPull() {
        guard webView.reload() != nil else {
            pullToRefreshControl.endRefreshing()
            return
        }
    }

    func completeNavigation() {
        activeNavigation = nil
        refreshNavigationState()
        refreshFavicon()
        publishCompletedNavigation()
    }

    /// The session keeps only the metadata a completed navigation reports, and
    /// `webView.title` can still be empty when WebKit finishes a new document.
    /// Read the settled document title first, then count the completion unless
    /// another navigation has replaced this document meanwhile. A move within
    /// the document while its title was read, such as a script router's first
    /// `replaceState`, belongs to this load, which finishes where the document
    /// is now.
    private func publishCompletedNavigation() {
        let committedNavigation = committedNavigationCount
        Task { @MainActor [weak self, weak webView] in
            guard let self, let webView else { return }
            let documentTitle = try? await webView.evaluateJavaScript("document.title") as? String
            guard activeNavigation == nil,
                committedNavigationCount == committedNavigation,
                let finishedURL = webView.url
            else { return }
            let title = documentTitle?.isEmpty == false ? documentTitle : webView.title
            completedNavigationCount &+= 1
            reporter.finished(finishedURL, title: title)
            updateUnderPageBackground()
        }
    }

    private func refreshFavicon() {
        guard navigationContext?.iconMode.followsPage == true,
            webView.url != nil
        else { return }
        faviconSession.refresh()
    }

    var siteThemeIconAccent: BrowserTabIconAccent? {
        guard let themeColor else { return nil }
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard themeColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha),
            alpha > 0
        else { return nil }
        return BrowserTabIconAccent(
            red: Double(red),
            green: Double(green),
            blue: Double(blue)
        )
    }

    /// Reacts to WebKit losing this page's web-content process, which the
    /// core recovers. On iOS this is most often routine eviction: the system
    /// reclaims a background tab's process to get its memory back, and the
    /// core brings such a page back once a window shows it.
    func recordWebContentTermination() {
        reportWebContentProcessStopped()
    }

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
        enginePage.zoom(to: zoom)
        return true
    }

    func prepareForNavigation(to url: URL?) {
        sitePermissionSession.resetMediaGrants()
        sitePermissionRequests.cancelAll()
        translation.reset()
        readerModeSession.invalidate()
        mediaSessionCoordinator?.prepareForNavigation()
        beginBlockedPopupNavigation()
        synchronizePopupPermission(for: url)
        faviconSession.invalidate()
        reporter.heading(to: url)
    }

    func updateUnderPageBackground() {
        webView.underPageBackgroundColor =
            completedNavigationCount == 0 ? .clear : themeColor
    }

    /// Tells the core the page's current navigation failed with `error`,
    /// which `replacedDocument` when it came after the new document took the
    /// page's place. A navigation that became a download or was cancelled is
    /// no failure, and only ends.
    func recordNavigationFailure(
        _ error: any Error,
        replacedDocument: Bool,
        navigation: WKNavigation?
    ) {
        guard isCurrentNavigation(navigation) else { return }
        activeNavigation = nil
        // A load that ends here commits no entry to take the core's identity.
        navigationHistory.expectEntry(nil)
        if let failure = PageFailure(
            error: error, replacedDocument: replacedDocument, fallbackURL: reporter.pendingURL ?? webView.url)
        {
            reporter.failed(failure)
        } else {
            reporter.interrupted()
        }
    }

    /// Brings WebKit's supplemental history up to date and tells the core what
    /// the page shows.
    func refreshNavigationState() {
        synchronizeNavigationHistory()
        reporter.stateChanged()
    }

    /// What WebKit shows for the page now: the document and its title,
    /// whether it loads, the page's
    /// security from its secure-content flag and the trust it kept, and the
    /// media WebKit last said it runs.
    private func snapshot(pendingURL: String?) -> PageSnapshot {
        let overrides = serverTrustOverrides
        let profileID = profileID
        return PageSnapshot(
            url: webView.url?.absoluteString,
            pendingURL: pendingURL,
            title: webView.title ?? "",
            isLoading: webView.isLoading,
            security: PageSecurity(
                webKitURL: webView.url,
                hasOnlySecureContent: webView.hasOnlySecureContent,
                serverTrust: webView.serverTrust,
                isApprovedOverride: { overrides.isApproved($0, for: profileID) }),
            media: pageEngine.knownMediaActivity)
    }

    /// Whether this page's own web view sent `scriptMessage`.
    ///
    /// A popup shares its opener's `WKUserContentController`, so the opener's
    /// user scripts run inside the popup's document and post to the opener's
    /// handlers. Without this check a popup's form would be read against the
    /// opener's top-level origin, and an accepted fill would be evaluated in the
    /// opener's web view against a frame belonging to the popup's.
    private func isOwnScriptMessage(_ scriptMessage: WKScriptMessage) -> Bool {
        scriptMessage.webView === webView
    }

    private func receiveLinkActivationMessage(_ message: WKScriptMessage) {
        guard isOwnScriptMessage(message),
            message.name == MobileLinkActivationContentBridge.messageHandlerName,
            let event = MobileLinkActivationEvent(body: message.body)
        else { return }

        if message.frameInfo.isMainFrame,
            let destinationURL = event.destinationURL,
            let normalizedSourceRect = event.normalizedSourceRect
        {
            downloadSourceStore.record(
                BrowserDownloadSourceCapture(
                    destinationURL: destinationURL,
                    normalizedSourceRect: normalizedSourceRect,
                    normalizedTouchPoint:
                        event.normalizedTouchPoint
                        ?? CGPoint(
                            x: normalizedSourceRect.midX,
                            y: normalizedSourceRect.midY
                        )
                )
            )
        }
    }

}

extension MobileBrowserPage: WebKitPageHosting {}
