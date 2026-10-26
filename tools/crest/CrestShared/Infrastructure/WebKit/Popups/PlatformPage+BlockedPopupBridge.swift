import WebKit

/// Blocked-popup reports from the WebKit content bridge.
extension BrowserPlatformPage {
    func receiveBlockedPopupMessage(_ message: WKScriptMessage) {
        if let sourceWebView = message.webView, sourceWebView !== webKitView {
            host?.routeBlockedPopupMessage(message)
            return
        }
        guard message.webView === webKitView,
            message.name == BrowserBlockedPopupContentBridge.messageHandlerName,
            message.frameInfo.isMainFrame,
            let body = message.body as? [String: Any],
            (body["version"] as? NSNumber)?.intValue == 1,
            body["event"] as? String == "blocked",
            body["userActivated"] as? Bool == false,
            let documentIdentifier = body["documentIdentifier"] as? String,
            !documentIdentifier.isEmpty,
            documentIdentifier.count <= 128,
            let frameURL = message.frameInfo.request.url,
            let origin = SiteOrigin(url: frameURL),
            let currentURL = webKitView?.url,
            SiteOrigin(url: currentURL) == origin,
            !permissionCenter.decision(for: .popups, origin: origin, in: spaceID).grants
        else { return }

        var nextState = blockedPopupState
        guard
            nextState.recordBlockedAttempt(
                documentIdentifier: documentIdentifier,
                origin: origin
            )
        else { return }
        blockedPopupState = nextState
    }
}
