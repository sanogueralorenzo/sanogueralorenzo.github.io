import AppKit
import Foundation
import WebKit

extension BrowserPage {
    /// The messages the notification bridge sends, by their actions.
    private static let hostedNotificationMessages: [any BrowserHostedNotificationMessage.Type] = [
        BrowserHostedNotificationPermissionQuery.self, BrowserHostedNotificationPermissionRequest.self,
        BrowserHostedNotificationCreation.self, BrowserHostedNotificationClosing.self,
    ]

    /// The bridge's per-document state lives with the WebKit adapter; another
    /// engine never posts through this bridge.
    var hostedNotificationDocumentIdentifier: String {
        get { webKitAdapter?.hostedNotificationDocumentIdentifier ?? "" }
        set { webKitAdapter?.hostedNotificationDocumentIdentifier = newValue }
    }

    /// Follows a change to the site's notification decision: the document is
    /// told the permission it now has. The page has already taken down what
    /// it may no longer show.
    func refreshHostedWebNotificationPermission() {
        guard let currentURL = live.displayURL ?? webKitView?.url,
            let origin = SiteOrigin(url: currentURL)
        else {
            return
        }
        let documentIdentifier = hostedNotificationDocumentIdentifier
        Task { @MainActor [weak self] in
            await self?.sendHostedNotificationPermission(
                requestID: "site-controls",
                origin: origin,
                requestsSystemAuthorization: false,
                documentIdentifier: documentIdentifier,
                frame: nil
            )
        }
    }

    func receiveHostedWebNotificationMessage(_ message: WKScriptMessage) {
        if let sourceWebView = message.webView, sourceWebView !== webKitView {
            host?.routeHostedWebNotificationMessage(message)
            return
        }
        guard hostedNotificationCenter != nil,
            message.webView === webKitView,
            message.frameInfo.isMainFrame,
            let requestURL = message.frameInfo.request.url,
            let origin = SiteOrigin(url: requestURL),
            SiteOrigin(message.frameInfo.securityOrigin) == origin,
            SecureOriginCheck(origin: origin).isAllowed,
            let body = message.body as? [String: Any],
            (body["version"] as? Int) == 1,
            let action = body["action"] as? String
        else { return }
        guard let kind = Self.hostedNotificationMessages.first(where: { $0.action == action }),
            let request = kind.init(body: body)
        else { return }
        request.handle(
            on: self,
            in: BrowserHostedNotificationDocument(
                identifier: hostedNotificationDocumentIdentifier, origin: origin, frame: message.frameInfo))
    }

    func beginHostedWebNotificationNavigation() {
        sitePermissionRequests.cancelAll()
        removeWebNotifications()
        hostedNotificationDocumentIdentifier = UUID().uuidString
    }

    func resolveHostedNotificationPermission(
        requestID: String,
        origin: SiteOrigin,
        hasUserActivation: Bool,
        documentIdentifier: String,
        frame: WKFrameInfo
    ) async {
        guard
            isCurrentHostedNotificationDocument(
                documentIdentifier,
                origin: origin
            )
        else { return }
        let decision = permissionCenter.decision(
            for: .notifications,
            origin: origin,
            in: spaceID
        )
        await NotificationPermissionRequest(decision: decision, hasUserActivation: hasUserActivation).action.respond(
            through: BrowserHostedNotificationPermissionResolution(
                page: self, requestID: requestID, origin: origin, hasUserActivation: hasUserActivation,
                documentIdentifier: documentIdentifier, frame: frame))
    }

    func sendHostedNotificationPermission(
        requestID: String,
        origin: SiteOrigin,
        requestsSystemAuthorization: Bool,
        documentIdentifier: String,
        frame: WKFrameInfo?
    ) async {
        guard
            isCurrentHostedNotificationDocument(
                documentIdentifier,
                origin: origin
            )
        else { return }
        let siteDecision = permissionCenter.decision(
            for: .notifications,
            origin: origin,
            in: spaceID
        )
        // The states are the Notifications API's. A site's saved verdict
        // gives them on its own, except a grant, which the system decides.
        let permission: BrowserWebPermissionState
        if let answered = BrowserWebPermissionState.answering(siteDecision.verdict) {
            permission = answered
        } else if let hostedNotificationCenter {
            permission =
                requestsSystemAuthorization
                ? .granting(await authorizedForSystemNotifications(requestIfNeeded: true))
                : .answering(await hostedNotificationCenter.currentAuthorization())
        } else {
            permission = .denied
        }
        guard
            isCurrentHostedNotificationDocument(
                documentIdentifier,
                origin: origin
            )
        else { return }
        sendHostedNotificationPermissionResponse(
            requestID: requestID,
            permission: permission,
            documentIdentifier: documentIdentifier,
            origin: origin,
            frame: frame
        )
    }

    /// Shows what the document posted through Crest's shared path, and tells
    /// the document whether it shows and when the person clicks it.
    func createHostedWebNotification(
        identifier: String,
        title: String,
        body: String,
        isSilent: Bool,
        origin: SiteOrigin,
        documentIdentifier: String
    ) async {
        let shown = await showWebNotification(
            BrowserHostedWebNotificationDelivery(
                identifier: "\(documentIdentifier).\(identifier)",
                title: title,
                body: body,
                origin: origin,
                isSilent: isSilent
            ),
            isPosted: { [weak self] in
                self?.isCurrentHostedNotificationDocument(documentIdentifier, origin: origin) ?? false
            },
            clicked: { [weak self] in
                self?.sendHostedNotificationEvent(
                    identifier: identifier,
                    event: "click",
                    documentIdentifier: documentIdentifier,
                    origin: origin
                )
            }
        )
        sendHostedNotificationEvent(
            identifier: identifier,
            event: shown ? "show" : "error",
            documentIdentifier: documentIdentifier,
            origin: origin
        )
    }

    /// Whether the system lets Crest show notifications, offering to recover
    /// a refusal and, when `requestIfNeeded`, asking the person when it has
    /// not decided.
    func authorizedForSystemNotifications(
        requestIfNeeded: Bool
    ) async -> Bool {
        guard let center = hostedNotificationCenter else { return false }
        var request: (@MainActor () async -> BrowserSystemAuthorization)?
        if requestIfNeeded { request = { await center.requestAuthorization() } }
        let access = BrowserSystemAuthorizationAccess(
            current: { await center.currentAuthorization() }, request: request,
            recover: recoverNotificationSystemAuthorization)
        let authorization = await center.currentAuthorization()
        return await authorization.authorizes(through: access)
    }

    func hasActiveUserGesture(in frame: WKFrameInfo) async -> Bool {
        guard let webView = webKitView else { return false }
        let result = try? await webView.callAsyncJavaScript(
            "return navigator.userActivation?.isActive === true;",
            arguments: [:],
            in: frame,
            contentWorld: .page
        )
        return result as? Bool ?? false
    }

    func hostedSystemIdentifier(for identifier: String) -> String {
        "\(hostedNotificationDocumentIdentifier).\(identifier)"
    }

    func sendHostedNotificationPermissionResponse(
        requestID: String,
        permission: BrowserWebPermissionState,
        documentIdentifier: String,
        origin: SiteOrigin,
        frame: WKFrameInfo?
    ) {
        sendHostedNotificationMessage(
            [
                "type": "permission",
                "requestID": requestID,
                "permission": permission.notificationSpelling,
            ],
            documentIdentifier: documentIdentifier,
            origin: origin,
            frame: frame
        )
    }

    private func sendHostedNotificationEvent(
        identifier: String,
        event: String,
        documentIdentifier: String,
        origin: SiteOrigin
    ) {
        sendHostedNotificationMessage(
            [
                "type": "event",
                "identifier": identifier,
                "event": event,
            ],
            documentIdentifier: documentIdentifier,
            origin: origin,
            frame: nil
        )
    }

    private func sendHostedNotificationMessage(
        _ message: [String: Any],
        documentIdentifier: String,
        origin: SiteOrigin,
        frame: WKFrameInfo?
    ) {
        guard
            isCurrentHostedNotificationDocument(
                documentIdentifier,
                origin: origin
            )
        else { return }
        let webView = webKitView
        Task { @MainActor [weak self, weak webView] in
            guard let self,
                isCurrentHostedNotificationDocument(
                    documentIdentifier,
                    origin: origin
                )
            else { return }
            _ = try? await webView?.callAsyncJavaScript(
                "globalThis.__crestHostedNotificationBridge?.receive(message);",
                arguments: ["message": message],
                in: frame,
                contentWorld: .page
            )
        }
    }

    func isCurrentHostedNotificationDocument(
        _ documentIdentifier: String,
        origin: SiteOrigin
    ) -> Bool {
        guard documentIdentifier == hostedNotificationDocumentIdentifier,
            let currentURL = webKitView?.url ?? live.displayURL,
            let currentOrigin = SiteOrigin(url: currentURL)
        else { return false }
        return currentOrigin == origin
    }
}
