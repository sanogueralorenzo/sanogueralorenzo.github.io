import WebKit

extension BrowserPlatformPage {
    func receiveGeolocationMessage(_ message: WKScriptMessage) {
        if let sourceWebView = message.webView, sourceWebView !== webKitView {
            host?.routeGeolocationMessage(message)
            return
        }
        geolocationCoordinator?.receive(message)
    }

    func beginGeolocationNavigation() {
        geolocationCoordinator?.beginNavigation()
    }

    func removeGeolocationRequests() {
        geolocationCoordinator?.cancelAll()
    }
}
