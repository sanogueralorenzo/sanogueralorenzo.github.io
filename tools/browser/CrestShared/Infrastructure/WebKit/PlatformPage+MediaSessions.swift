import WebKit

extension BrowserPlatformPage {
    func receiveMediaSessionMessage(_ message: WKScriptMessage) {
        guard message.webView === webKitView else {
            host?.routeMediaSessionMessage(message)
            return
        }
        mediaSessionCoordinator?.receive(message)
        refreshMediaActivity()
    }

    /// Asks WebKit what media the page runs, and tells the core when that
    /// changed: playback starting, stopping or ending in any frame, capture,
    /// or Picture in Picture. The core decides what memory pressure may
    /// unload from what the page last told it.
    func refreshMediaActivity() {
        guard let engine = webKitEngine else { return }
        Task { @MainActor [weak self, weak engine] in
            guard let engine, await engine.refreshMediaActivity() else { return }
            self?.navigationReporter?.stateChanged()
        }
    }

    func performMediaSessionAction(
        _ action: MediaSessionAction,
        documentIdentifier: String
    ) {
        mediaSessionCoordinator?.perform(
            action,
            documentIdentifier: documentIdentifier
        )
    }

    func setMediaSessionMuted(
        _ muted: Bool,
        documentIdentifier: String
    ) {
        mediaSessionCoordinator?.setMuted(
            muted,
            documentIdentifier: documentIdentifier
        )
    }
}
