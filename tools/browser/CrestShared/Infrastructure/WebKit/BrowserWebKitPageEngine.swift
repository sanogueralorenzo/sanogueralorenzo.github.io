import Foundation
import Observation
import WebKit

/// The same WebKit port serves desktop and mobile. Supplemental same-document
/// history stays with its engine rather than leaking WKBackForwardListItem to UI.
@Observable @MainActor
final class BrowserWebKitPageEngine: BrowserPageEngine {
    let registration = BrowserEngineRegistration.webKit
    let webView: WKWebView
    var history = BrowserPageNavigationHistory()
    var nativeView: BrowserEngineView { webView }
    /// WebKit reports its native video presentation only to the UI delegate,
    /// which covers PiP entered from its own controls and cross-origin frames.
    /// The page that owns the delegate forwards the callback here.
    @ObservationIgnored var hasVideoInPictureInPicture = false
    /// What media the page ran when WebKit last answered, which the page's
    /// snapshot reports.
    @ObservationIgnored private(set) var knownMediaActivity: PageMediaActivity = []
    @ObservationIgnored private var stagedRequest: URLRequest?
    #if os(macOS)
        @ObservationIgnored private var closeCompletion: (@MainActor (Bool) -> Void)?
        @ObservationIgnored private var closeTimeout: Task<Void, Never>?
    #endif

    init(webView: WKWebView) { self.webView = webView }

    /// The binding's page this port serves, which stages links through the
    /// core.
    @ObservationIgnored weak var enginePage: WebKitEnginePage?

    /// The link the core staged as the page's first load, through the
    /// binding, which its first load of that address replays.
    func stageNavigation(_ navigation: BrowserEngineNavigation, expecting url: URL) -> Bool {
        enginePage?.stage(navigation, expecting: url) ?? false
    }

    /// Keeps `request` as the page's first load, while the page has loaded
    /// nothing and keeps no other; false otherwise.
    func stage(_ request: URLRequest) -> Bool {
        guard stagedRequest == nil, webView.url == nil else { return false }
        stagedRequest = request
        return true
    }

    /// WebKit's own history of the page, once a document committed; a web
    /// view that never loaded has nothing worth keeping.
    func savedHistory() -> Data? {
        guard webView.backForwardList.currentItem != nil else { return nil }
        return webView.interactionState as? Data
    }

    /// Restores history `savedHistory()` kept; false when WebKit dropped it,
    /// which leaves the web view with no current entry.
    func restoreHistory(_ state: Data) -> Bool {
        // Supplements describe the list being replaced.
        history = BrowserPageNavigationHistory()
        webView.interactionState = state
        return webView.backForwardList.currentItem != nil
    }

    var currentURL: URL? { webView.url }

    @discardableResult
    func synchronizeHistory() -> URL? {
        history.synchronize(with: webView.backForwardList)
        return webView.backForwardList.currentItem?.url
    }

    /// The page's history as the core keeps it, brought up to date with
    /// WebKit's own list first.
    var reportedHistory: (entries: [PageHistoryEntry], current: Int)? {
        history.synchronize(with: webView.backForwardList)
        return history.reported
    }

    func load(_ request: URLRequest) {
        if let staged = stagedRequest {
            stagedRequest = nil
            if staged.url == request.url {
                webView.load(staged)
                return
            }
        }
        // A local document needs an explicit read-access root before WebKit will
        // give the document its own file origin; an ordinary request would load
        // the page without its stylesheets, scripts or images. The folder holding
        // the file is that root, which is what a saved page's resources sit in.
        if let url = request.url, ExternalLocalDocument.accepts(url) {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
            return
        }
        webView.load(request)
    }
    /// Shows the history entry `entryID` names, as WebKit keeps it; false
    /// when the page no longer keeps it.
    func goToHistoryEntry(_ entryID: UUID) -> Bool {
        history.synchronize(with: webView.backForwardList)
        guard let item = history.item(entryID) else { return false }
        // WebKit starts nothing for an item it no longer keeps.
        return webView.go(to: item) != nil
    }
    func reload(bypassingCache: Bool) {
        if bypassingCache { webView.reloadFromOrigin() } else { webView.reload() }
    }
    func mediaActivity() async -> PageMediaActivity? {
        let state = await withCheckedContinuation { continuation in
            webView.requestMediaPlaybackState { continuation.resume(returning: $0) }
        }
        var activity: PageMediaActivity = []
        if state == .playing { activity.insert(.playing) }
        if webView.cameraCaptureState != .none || webView.microphoneCaptureState != .none {
            activity.insert(.capturing)
        }
        if hasVideoInPictureInPicture { activity.insert(.pictureInPicture) }
        return activity
    }

    /// Asks WebKit what media the page runs now, and answers whether that
    /// differs from what it said before.
    func refreshMediaActivity() async -> Bool {
        guard let activity = await mediaActivity(), activity != knownMediaActivity else { return false }
        knownMediaActivity = activity
        return true
    }
    #if os(macOS)
        /// Asks the page's beforeunload handlers whether it may close. WebKit runs
        /// them for an embedder close only through `_tryClose`, which answers
        /// immediately when no document in the process needs the event, and
        /// otherwise ends in `webViewDidClose` or a beforeunload panel the person
        /// can decline. Approval leaves the page alive; the caller releases it.
        func prepareToClose(completion: @escaping @MainActor (Bool) -> Void) {
            let selector = NSSelectorFromString("_tryClose")
            guard closeCompletion == nil else {
                completion(false)
                return
            }
            guard webView.responds(to: selector) else {
                completion(true)
                return
            }
            typealias TryClose = @convention(c) (AnyObject, Selector) -> Bool
            let tryClose = unsafeBitCast(webView.method(for: selector), to: TryClose.self)
            if tryClose(webView, selector) {
                completion(true)
                return
            }
            closeCompletion = completion
            scheduleCloseTimeout()
        }

        /// The person is deciding; a prompt has no time limit.
        func beforeUnloadPanelWillAppear() { closeTimeout?.cancel() }

        /// Staying ends the close here: WebKit sends nothing more. Leaving still
        /// waits for WebKit's close callback.
        func beforeUnloadPanelDidFinish(leaving: Bool) {
            guard closeCompletion != nil else { return }
            if leaving { scheduleCloseTimeout() } else { finishClose(false) }
        }

        /// Returns true when the callback answers this port's own close request,
        /// so it must not be treated as the page calling `window.close()`.
        func webViewDidClose() -> Bool {
            guard closeCompletion != nil else { return false }
            finishClose(true)
            return true
        }

        // WebKit already closes after its own short timeout when the web process
        // does not answer; this only guards against a callback that never comes.
        private func scheduleCloseTimeout() {
            closeTimeout?.cancel()
            closeTimeout = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
                self?.finishClose(true)
            }
        }

        private func finishClose(_ allowed: Bool) {
            closeTimeout?.cancel()
            closeTimeout = nil
            let completion = closeCompletion
            closeCompletion = nil
            completion?(allowed)
        }
    #endif

}
