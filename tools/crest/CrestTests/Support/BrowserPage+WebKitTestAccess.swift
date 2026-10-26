import AppKit
import WebKit

@testable import Crest

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
            openModifiedLink: openModifiedLink,
            openPeek: openPeek,
            handleLinkDrag: handleLinkDrag,
            splitLinkHost: splitLinkHost,
            linkDestinationHost: linkDestinationHost,
            opensExternalURL: opensExternalURL
        )
    }

    /// The web view behind a page the WebKit composition built. The suites
    /// drive WebKit pages directly; a page from another engine is a test error.
    var webView: WKWebView {
        guard let webView = webKitView else { preconditionFailure("The page is not hosted by WebKit.") }
        return webView
    }
}
