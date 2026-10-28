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
        defaultPageZoom: CGFloat = BrowserDefaultPageZoomStore.defaultLevel,
        openNewTab: @escaping (URL) -> Void = { _ in },
        openModifiedLink: @escaping (URLRequest, UUID, Bool) -> Void = { _, _, _ in },
        splitLinkHost: BrowserSplitLinkHost = .unavailable,
        linkDestinationHost: BrowserLinkDestinationHost = .unavailable,
        opensExternalURL: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) }
    ) {
        self.init(
            corePage: corePage,
            engine: BrowserWebKitPageAdapter(
                page: webKitPage,
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
            defaultPageZoom: defaultPageZoom,
            openNewTab: openNewTab,
            openModifiedLink: openModifiedLink,
            splitLinkHost: splitLinkHost,
            linkDestinationHost: linkDestinationHost,
            opensExternalURL: opensExternalURL
        )
    }

    var webView: WKWebView { webKitView }
}
