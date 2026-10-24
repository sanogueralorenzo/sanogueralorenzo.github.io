import AppKit
import Foundation
import WebKit

/// The page's WebKit-only state, read by its WebKit delegate conformances and
/// bridges. Each is empty when another engine hosts the page.
extension BrowserPage {
    /// A page hosting the desktop `WKWebView` WebKit's binding built as
    /// `webKitPage`, for a page the core opened on WebKit.
    convenience init(
        corePage: CorePage,
        webKitPage: WebKitEnginePage,
        dialogPresenter: BrowserDialogPresenter,
        downloadCenter: BrowserDownloadCenter,
        permissionCenter: BrowserSitePermissionCenter,
        geolocationService: any BrowserGeolocationServicing =
            BrowserGeolocationSystemService(),
        recoverGeolocationSystemAuthorization:
            BrowserGeolocationCoordinator.RecoverSystemAuthorization? = nil,
        hostedNotificationCenter:
            (any BrowserHostedWebNotificationCentering)? = nil,
        recoverNotificationSystemAuthorization:
            (@MainActor () async -> Void)? = nil,
        serverTrustOverrides: BrowserServerTrustOverrideStore = BrowserServerTrustOverrideStore(),
        mediaSessionStore: BrowserMediaSessionStore? = nil,
        spaceID: UUID,
        profileID: UUID,
        spaceName: String,
        contentRuleList: WKContentRuleList? = nil,
        allowsCredentialAccess: Bool = true,
        isCredentialAccessEnabled: Bool = true,
        defaultPageZoom: CGFloat = BrowserDefaultPageZoomStore.defaultLevel,
        loadHTTPAuthenticationCredential:
            @escaping BrowserHTTPAuthenticationSession.LoadCredential = { _ in nil },
        saveHTTPAuthenticationCredential:
            @escaping BrowserHTTPAuthenticationSession.SaveCredential = { _ in },
        openNewTab: @escaping (URL) -> Void,
        openModifiedLink: @escaping (URLRequest, UUID, Bool) -> Void = { _, _, _ in },
        openPeek: @escaping (BrowserPeekRequest) -> Void = { _ in },
        handleLinkDrag: @escaping (BrowserPeekInteractionEvent) -> Void = { _ in },
        splitLinkHost: BrowserSplitLinkHost = .unavailable,
        linkDestinationHost: BrowserLinkDestinationHost = .unavailable,
        opensExternalURL: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) }
    ) {
        self.init(
            corePage: corePage,
            engine: BrowserWebKitPageAdapter(
                page: webKitPage,
                contentRuleList: contentRuleList,
                geolocationService: geolocationService,
                recoverGeolocationSystemAuthorization: recoverGeolocationSystemAuthorization
            ),
            dialogPresenter: dialogPresenter,
            downloadCenter: downloadCenter,
            permissionCenter: permissionCenter,
            hostedNotificationCenter: hostedNotificationCenter,
            recoverNotificationSystemAuthorization: recoverNotificationSystemAuthorization,
            serverTrustOverrides: serverTrustOverrides,
            mediaSessionStore: mediaSessionStore,
            spaceID: spaceID,
            profileID: profileID,
            spaceName: spaceName,
            allowsCredentialAccess: allowsCredentialAccess,
            isCredentialAccessEnabled: isCredentialAccessEnabled,
            defaultPageZoom: defaultPageZoom,
            loadHTTPAuthenticationCredential: loadHTTPAuthenticationCredential,
            saveHTTPAuthenticationCredential: saveHTTPAuthenticationCredential,
            openNewTab: openNewTab,
            openModifiedLink: openModifiedLink,
            openPeek: openPeek,
            handleLinkDrag: handleLinkDrag,
            splitLinkHost: splitLinkHost,
            linkDestinationHost: linkDestinationHost,
            opensExternalURL: opensExternalURL
        )
    }

    var webKitAdapter: BrowserWebKitPageAdapter? { engineAdapter as? BrowserWebKitPageAdapter }
    var webKitView: WKWebView? { webKitAdapter?.webView }

    var activeNavigation: WKNavigation? {
        get { webKitAdapter?.activeNavigation }
        set { webKitAdapter?.activeNavigation = newValue }
    }

    /// Supplemental history for link entries WebKit leaves out of its lists.
    var navigationHistory: BrowserPageNavigationHistory {
        get { webKitAdapter?.webKit.history ?? BrowserPageNavigationHistory() }
        set { webKitAdapter?.webKit.history = newValue }
    }

    var geolocationCoordinator: BrowserGeolocationCoordinator? { webKitAdapter?.geolocationCoordinator }

    func applyContentBlocking(
        policy: ContentBlockingPolicy,
        balancedRuleLists: [WKContentRuleList],
        activation: BrowserContentRuleListActivation = .onNextNavigation
    ) {
        webKitAdapter?.applyContentBlocking(
            policy: policy,
            balancedRuleLists: balancedRuleLists,
            reloadsImmediately: activation == .immediately && pageEngine.currentURL != nil
        )
    }

    func updateUnderPageBackground() {
        webKitView?.underPageBackgroundColor =
            completedNavigationCount == 0 ? .clear : nil
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
        guard isCurrentNavigation(navigation), let reporter = webKitAdapter?.reporter else { return }
        activeNavigation = nil
        // A load that ends here commits no entry to take the core's identity.
        navigationHistory.expectEntry(nil)
        if let failure = PageFailure(
            error: error, replacedDocument: replacedDocument, fallbackURL: reporter.pendingURL ?? webKitView?.url)
        {
            reporter.failed(failure)
        } else {
            reporter.interrupted()
        }
    }

    /// Whether this page's own web view sent `scriptMessage`.
    ///
    /// A popup shares its opener's `WKUserContentController`, so the opener's
    /// user scripts run inside the popup's document and post to the opener's
    /// handlers. Without this check a popup's form would be read against the
    /// opener's top-level origin, and an accepted fill would be evaluated in the
    /// opener's web view against a frame belonging to the popup's.
    private func isOwnScriptMessage(_ scriptMessage: WKScriptMessage) -> Bool {
        scriptMessage.webView === webKitView
    }

    func receiveCredentialMessage(_ scriptMessage: WKScriptMessage) {
        guard let webView = webKitView else { return }
        credentialSession.receive(scriptMessage, in: webView)
    }

    /// Records the link the person just right-clicked, moments before WebKit
    /// hands AppKit the menu that right-click opens.
    func receiveLinkContextMessage(_ scriptMessage: WKScriptMessage) {
        guard isOwnScriptMessage(scriptMessage),
            scriptMessage.name
                == BrowserLinkContextContentBridge.messageHandlerName
        else { return }
        if scriptMessage.frameInfo.isMainFrame,
            let activation = BrowserDownloadSourceCapture(
                messageBody: scriptMessage.body
            )
        {
            downloadSourceStore.record(activation)
            return
        }
        linkContextCapture.record(
            body: scriptMessage.body,
            documentURL: scriptMessage.frameInfo.request.url,
            isMainFrame: scriptMessage.frameInfo.isMainFrame
        )
    }
}

// MARK: - WebKit hosting

extension BrowserPage: WebKitPageHosting {
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
        navigationReporter?.reportHistoryAgain()
    }
}
