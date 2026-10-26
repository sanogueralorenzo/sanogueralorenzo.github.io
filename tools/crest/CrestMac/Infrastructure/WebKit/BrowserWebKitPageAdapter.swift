import AppKit
import Combine
import Foundation
import WebKit

/// The desktop WebKit adapter for one page: the `BrowserDesktopWebView`, its
/// delegates and user content controller bridges, and the page controllers
/// built on the web view. The page's WebKit delegate conformances read their
/// per-page WebKit state from here.
@MainActor
final class BrowserWebKitPageAdapter: BrowserPageEngineAdapter {
    // MARK: - Variables

    /// What WebKit's binding built for the page, which this adapter keeps
    /// while the page lives.
    let webKitPage: WebKitEnginePage
    let webKit: BrowserWebKitPageEngine
    let webView: BrowserDesktopWebView
    var engine: any BrowserPageEngine { webKit }
    let enginePage: EnginePage

    /// False when this page shares the opener's `WKUserContentController`, which
    /// every popup does: WebKit copies the opener's configuration and the copy
    /// keeps the same controller. Installing the same script message handler
    /// twice on it throws, and removing one would strip it from the opener.
    let ownsUserContentController: Bool
    var activeNavigation: WKNavigation?
    /// Tells the core what the page shows and what its navigations and icon
    /// do, once the page is attached.
    private(set) var reporter: EnginePageReporter?
    /// The document's address as WebKit last published it.
    private var documentURL: URL?
    let contentRuleSession: BrowserPageContentRuleSession
    var geolocationCoordinator: BrowserGeolocationCoordinator?
    private let geolocationService: any BrowserGeolocationServicing
    private let recoverGeolocationSystemAuthorization: BrowserGeolocationCoordinator.RecoverSystemAuthorization?
    private weak var page: BrowserPage?
    private var observations: Set<AnyCancellable> = []
    private var credentialMessageProxy: BrowserScriptMessageProxy?
    private var linkContextMessageProxy: BrowserScriptMessageProxy?
    private var userActivityMessageProxy: BrowserScriptMessageProxy?
    private var geolocationMessageProxy: BrowserScriptMessageProxy?
    private var blockedPopupMessageProxy: BrowserScriptMessageProxy?
    private var mediaSessionMessageProxy: BrowserScriptMessageProxy?
    private var hostedNotificationMessageProxy: BrowserScriptMessageProxy?
    /// Names the document the hosted notification bridge answers; a new one
    /// begins with each navigation.
    var hostedNotificationDocumentIdentifier = UUID().uuidString

    /// Crest's own Picture in Picture, which reports the page's media again
    /// whenever it starts or stops keeping the page's video on screen.
    private(set) lazy var pictureInPicture: (any BrowserPagePictureInPictureController)? = {
        let controller = BrowserPictureInPicturePageController(webView: webView)
        controller.residencyProtectionChanged = { [weak self] in self?.reporter?.stateChanged() }
        return controller
    }()
    private(set) lazy var linkHover: BrowserLinkHoverController? = BrowserLinkHoverController(webView: webView)
    private(set) lazy var linkDrag: BrowserLinkDragController? = BrowserLinkDragController(
        webView: webView,
        context: { [weak self] in self?.page?.navigationContext },
        dragsLinksToPeek: { [weak self] in self?.page?.corePage.linkPreferences?.dragsLinksToPeek == true },
        handle: { [weak self] event in self?.page?.handleLinkDrag(event) }
    )
    private(set) lazy var readerModeSession: BrowserReaderModeSession? = page.map {
        BrowserReaderModeSession(
            document: BrowserWebKitReaderModeDocument(webView: webView, translation: $0.translation))
    }
    private(set) lazy var faviconSession: BrowserFaviconSession? = page.map {
        BrowserFaviconSession(
            document: BrowserWebKitFaviconDocument(webView: webView, profileID: $0.profileID),
            policy: .delayedDocumentIcons,
            receive: { [weak self] data in
                self?.page?.receive(BrowserPageFaviconFetched(data: data, source: nil))
                self?.reporter?.foundIcon(data, at: self?.webView.url)
            }
        )
    }

    var isContentBlockingActive: Bool { contentRuleSession.isActive }
    var credentialEvaluator: BrowserCredentialSession.Evaluate? {
        BrowserCredentialSession.evaluator(in: webView)
    }
    var translationDocument: BrowserTranslationDocument? { BrowserTranslationDocument(webView: webView) }

    // MARK: - Initializers

    /// The adapter over the page WebKit's binding built. `contentRuleList` is
    /// a rule list the page applies beside its Space's.
    init(
        page webKitPage: WebKitEnginePage,
        contentRuleList: WKContentRuleList? = nil,
        geolocationService: any BrowserGeolocationServicing = BrowserGeolocationSystemService(),
        recoverGeolocationSystemAuthorization: BrowserGeolocationCoordinator.RecoverSystemAuthorization? = nil
    ) {
        guard let webView = webKitPage.webView as? BrowserDesktopWebView else {
            preconditionFailure("WebKit's binding built a web view other than the desktop one.")
        }
        self.webKitPage = webKitPage
        enginePage = webKitPage.makeEnginePage()
        self.webView = webView
        webKit = webKitPage.engine
        contentRuleSession = BrowserPageContentRuleSession(
            ruleLists: webKitPage.contentRuleLists,
            additionalRuleList: contentRuleList
        )
        ownsUserContentController = webKitPage.ownsUserContentController
        self.geolocationService = geolocationService
        self.recoverGeolocationSystemAuthorization = recoverGeolocationSystemAuthorization
    }

    // MARK: - Actions - Lifecycle

    func makeMediaSessionCoordinator(
        for page: BrowserPage,
        store: BrowserMediaSessionStore
    ) -> BrowserMediaSessionPageCoordinator? {
        if ownsUserContentController {
            mediaSessionMessageProxy = BrowserMediaSessionContentBridge.install(
                in: webView.configuration.userContentController
            ) { [weak page] message in
                page?.receiveMediaSessionMessage(message)
            }
        }
        return BrowserMediaSessionPageCoordinator(
            webView: webView, endpoint: page, store: store,
            owner: page.mediaSessionOwner, fallbackTitle: page.mediaSessionFallbackTitle)
    }

    func attach(to page: BrowserPage, allowsCredentialAccess: Bool) {
        self.page = page
        reporter = EnginePageReporter(
            page: page.corePage,
            snapshot: { [weak self] pendingURL in
                self?.snapshot(pendingURL: pendingURL)
                    ?? PageSnapshot(
                        url: nil, pendingURL: pendingURL, title: "", isLoading: false, security: PageSecurity.none,
                        media: [])
            },
            history: { [weak self] in self?.webKit.reportedHistory })
        webView.menuHost = page
        webView.linkHover = linkHover
        webView.linkDrag = linkDrag
        webView.isInspectable = true
        webView.navigationDelegate = page
        webView.uiDelegate = page
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        webView.allowsLinkPreview = true
        observeWebViewState()
        let controller = webView.configuration.userContentController
        if allowsCredentialAccess, ownsUserContentController {
            credentialMessageProxy = BrowserCredentialContentBridge.install(in: controller) { [weak page] message in
                page?.receiveCredentialMessage(message)
            }
        }
        // Private and isolated launches split exactly like a standard one, and
        // the bridge reports a destination rather than storing anything, so the
        // only gate is the shared-controller one every bridge has: a popup runs
        // its opener's scripts against its opener's handlers.
        if ownsUserContentController {
            BrowserLinkHoverContentBridge.install(in: controller)
            BrowserLinkDragContentBridge.install(in: controller)
            linkContextMessageProxy = BrowserLinkContextContentBridge.install(in: controller) { [weak page] message in
                page?.receiveLinkContextMessage(message)
            }
            blockedPopupMessageProxy = BrowserBlockedPopupContentBridge.install(in: controller) { [weak page] message in
                page?.receiveBlockedPopupMessage(message)
            }
        }
        let dialogPresenter = page.dialogPresenter
        geolocationCoordinator = BrowserGeolocationCoordinator(
            webView: webView,
            permissionCenter: page.permissionCenter,
            service: geolocationService,
            spaceID: page.spaceID,
            askSite: { [webKitPage] origin, topLevelOrigin in
                await webKitPage.ask(
                    PermissionQuestion(permission: .location, origin: origin, topLevelOrigin: topLevelOrigin))
            },
            recoverSystemAuthorization:
                recoverGeolocationSystemAuthorization
                ?? { await dialogPresenter.recoverGeolocationSystemAuthorization() }
        )
        if ownsUserContentController {
            geolocationMessageProxy = BrowserGeolocationContentBridge.install(in: controller) { [weak page] message in
                page?.receiveGeolocationMessage(message)
            }
        }
        if page.hostedNotificationCenter != nil, ownsUserContentController {
            hostedNotificationMessageProxy = BrowserHostedWebNotificationContentBridge.install(
                in: controller
            ) { [weak page] message in
                page?.receiveHostedWebNotificationMessage(message)
            }
        }
        // Last, so a page the core brings back restores into a page that
        // hears its navigations.
        webKitPage.attach(page)
    }

    func detach(from page: BrowserPage) {
        enginePage.close()
        webView.linkHover = nil
        webView.linkDrag = nil
        webView.stopLoading()
        webView.removeFromSuperview()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.menuHost = nil
        observations.removeAll()
        page.removeGeolocationRequests()
        defer { geolocationCoordinator = nil }
        guard ownsUserContentController else {
            // A popup shares its opener's content controller. Removing handlers
            // here would silence them for the opener too.
            credentialMessageProxy = nil
            linkContextMessageProxy = nil
            userActivityMessageProxy = nil
            geolocationMessageProxy = nil
            blockedPopupMessageProxy = nil
            hostedNotificationMessageProxy = nil
            mediaSessionMessageProxy = nil
            return
        }
        let controller = webView.configuration.userContentController
        func remove(_ proxy: AnyObject?, name: String, world: WKContentWorld) {
            guard proxy != nil else { return }
            controller.removeScriptMessageHandler(forName: name, contentWorld: world)
        }
        remove(
            credentialMessageProxy, name: BrowserCredentialContentBridge.messageHandlerName,
            world: BrowserCredentialContentBridge.contentWorld)
        credentialMessageProxy = nil
        remove(
            linkContextMessageProxy, name: BrowserLinkContextContentBridge.messageHandlerName,
            world: BrowserLinkContextContentBridge.contentWorld)
        linkContextMessageProxy = nil
        remove(
            userActivityMessageProxy, name: BrowserUserActivityBridge.messageHandlerName,
            world: BrowserUserActivityBridge.contentWorld)
        userActivityMessageProxy = nil
        remove(
            geolocationMessageProxy, name: BrowserGeolocationContentBridge.messageHandlerName,
            world: BrowserGeolocationContentBridge.contentWorld)
        geolocationMessageProxy = nil
        remove(
            blockedPopupMessageProxy, name: BrowserBlockedPopupContentBridge.messageHandlerName,
            world: BrowserBlockedPopupContentBridge.contentWorld)
        blockedPopupMessageProxy = nil
        remove(
            hostedNotificationMessageProxy, name: BrowserHostedWebNotificationContentBridge.messageHandlerName,
            world: BrowserHostedWebNotificationContentBridge.contentWorld)
        hostedNotificationMessageProxy = nil
        remove(
            mediaSessionMessageProxy, name: BrowserMediaSessionContentBridge.messageHandlerName,
            world: BrowserMediaSessionContentBridge.contentWorld)
        mediaSessionMessageProxy = nil
    }

    // MARK: - Actions - Page services

    func install(_ focusRestoration: BrowserWebFocusRestorationController) {
        webView.focusRestoration = focusRestoration
    }

    func monitorUserActivity(for page: BrowserPage) {
        guard ownsUserContentController, userActivityMessageProxy == nil else { return }
        userActivityMessageProxy = BrowserUserActivityBridge.install(
            in: webView.configuration.userContentController
        ) { [weak page] in
            page?.receive(BrowserPageInteracted())
        }
    }

    func styleVisitedLinks(history: [HistoryEntryState]) async {
        await BrowserVisitedLinkStyler.apply(history: history, to: webView)
    }

    /// WebKit geolocation observes the permission centre itself; the hosted
    /// notification bridge is told so the document sees the new permission.
    func sitePermissionDidChange(_ permission: SitePermission, on page: BrowserPage) {
        guard permission == .notifications else { return }
        page.refreshHostedWebNotificationPermission()
    }

    /// A private WebKit page is private through its website data store.
    func setPrivateBrowsing(_ isPrivate: Bool) {}

    func applyContentBlocking(
        policy: ContentBlockingPolicy,
        balancedRuleLists: [WKContentRuleList],
        reloadsImmediately: Bool
    ) {
        contentRuleSession.apply(
            policy: policy,
            balancedRuleLists: balancedRuleLists,
            to: webView,
            reloadsImmediately: reloadsImmediately
        )
    }

    // MARK: - Actions - Observation

    private func observeWebViewState() {
        webView.publisher(for: \.url, options: [.initial, .new]).sink { [weak self] _ in
            // WebKit publishes URL before finishing its back-forward-list
            // mutation. Read the settled URL and list together on the next turn.
            Task { @MainActor in
                guard let self else { return }
                let previous = self.documentURL
                self.documentURL = self.webView.url
                self.page?.receive(BrowserPageURLChanged(previous: previous, current: self.webView.url))
                self.reporter?.stateChanged()
                self.reportMoveWithinDocument()
            }
        }
        .store(in: &observations)
        webView.publisher(for: \.title, options: [.initial, .new]).sink { [weak self] _ in
            MainActor.assumeIsolated {
                self?.page?.receive(BrowserPageTitleChanged())
                self?.reporter?.titleChanged()
            }
        }
        .store(in: &observations)
        webView.publisher(for: \.estimatedProgress, options: [.initial, .new]).sink { [weak self] value in
            MainActor.assumeIsolated { self?.page?.receive(BrowserPageProgressChanged(progress: value)) }
        }
        .store(in: &observations)
        webView.publisher(for: \.isLoading, options: [.initial, .new]).sink { [weak self] _ in
            MainActor.assumeIsolated {
                self?.page?.receive(BrowserPageHistoryChanged())
                self?.page?.refreshMediaActivity()
            }
        }
        .store(in: &observations)
        webView.publisher(for: \.hasOnlySecureContent, options: [.initial, .new]).sink { [weak self] _ in
            MainActor.assumeIsolated { self?.reporter?.stateChanged() }
        }
        .store(in: &observations)
        webView.publisher(for: \.serverTrust, options: [.new]).sink { [weak self] _ in
            MainActor.assumeIsolated { self?.reporter?.stateChanged() }
        }
        .store(in: &observations)
        webView.publisher(for: \.cameraCaptureState, options: [.new]).sink { [weak self] _ in
            MainActor.assumeIsolated { self?.page?.refreshMediaActivity() }
        }
        .store(in: &observations)
        webView.publisher(for: \.microphoneCaptureState, options: [.new]).sink { [weak self] _ in
            MainActor.assumeIsolated { self?.page?.refreshMediaActivity() }
        }
        .store(in: &observations)
        webView.publisher(for: \.themeColor, options: [.initial, .new]).sink { [weak self] value in
            MainActor.assumeIsolated {
                self?.page?.receive(BrowserPageThemeColorChanged(color: value))
                self?.reporter?.themeChanged(self?.page?.siteThemeIconAccent)
            }
        }
        .store(in: &observations)
        webView.publisher(for: \.canGoBack, options: [.initial, .new]).sink { [weak self] _ in
            MainActor.assumeIsolated { self?.page?.receive(BrowserPageHistoryChanged()) }
        }
        .store(in: &observations)
        webView.publisher(for: \.canGoForward, options: [.initial, .new]).sink { [weak self] _ in
            MainActor.assumeIsolated { self?.page?.receive(BrowserPageHistoryChanged()) }
        }
        .store(in: &observations)
    }

    /// WebKit tells its delegate nothing about a move within the document,
    /// such as `history.pushState` or a fragment. The address changing while
    /// nothing loads, neither a request Crest made nor a navigation WebKit
    /// started, is that move.
    private func reportMoveWithinDocument() {
        guard activeNavigation == nil, !webView.isLoading, let url = webView.url else { return }
        reporter?.movedWithinDocument(to: url)
    }

    /// What WebKit shows for the page now: the document and its title,
    /// whether it loads, the page's
    /// security from its secure-content flag and the trust it kept, and the
    /// media WebKit last said it runs, with Picture in Picture while Crest's
    /// own controller holds or is entering it, so memory pressure never
    /// unloads that video.
    private func snapshot(pendingURL: String?) -> PageSnapshot? {
        guard let page else { return nil }
        let overrides = page.serverTrustOverrides
        let profileID = page.profileID
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
            media: pictureInPicture?.protectsPageResidency == true
                ? webKit.knownMediaActivity.union(.pictureInPicture) : webKit.knownMediaActivity)
    }
}
