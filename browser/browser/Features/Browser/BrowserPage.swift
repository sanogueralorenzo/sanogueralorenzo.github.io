import AppKit
import Foundation
import Observation
import WebKit

@MainActor
@Observable
final class BrowserPage: NSObject, WKNavigationDelegate, WKUIDelegate, Identifiable {
    // MARK: - Variables

    let id: UUID
    let spaceID: UUID
    let webView: WKWebView
    let contentBlocker: BrowserContentBlocking
    let loading: BrowserPageLoading
    let documentActivity: BrowserDocumentActivity
    var title = ""
    var url: URL?
    var favicon: Data?
    var isLoading = false
    private(set) var waitsForContentBlocking = false
    var canGoBack = false
    var canGoForward = false
    var failure: String?
    var isPlaying = false
    var mediaTitle = ""
    var lastSelected = Date()
    var translationRequest = 0
    var documentRevision = 0
    @ObservationIgnored var pendingNavigationURL: URL?
    var hasPictureInPicture = false
    @ObservationIgnored var pictureInPicture: BrowserPictureInPicturePageController?
    var isReaderMode = false
    var readerAvailable = false
    var mediaArtist = ""
    var mediaActions: Set<String> = []
    var hasMedia = false
    var mediaIsMuted = false
    var nowPlayingHidden = false
    var mediaDuration = 0.0
    var mediaElapsed = 0.0
    @ObservationIgnored var mediaFrame: WKFrameInfo?
    var hostingWindowID: UUID?
    var mirrorImage: NSImage?
    var isSharedAcrossWindows: Bool {
        (owner?.owner.contexts.values.filter { !$0.isClosed && $0.visiblePages.contains(where: { $0.id == id }) }.count
            ?? 0) > 1
    }
    var scriptMayClose = false
    @ObservationIgnored var closeContinuation: CheckedContinuation<Bool, Never>?
    @ObservationIgnored var closeTask: Task<Void, Never>?
    @ObservationIgnored var automaticClose = false
    @ObservationIgnored var restoreState: BrowserDocumentState?
    @ObservationIgnored var siteController: BrowserSiteController?
    @ObservationIgnored var uploadScopes: [URL] = []
    @ObservationIgnored weak var owner: BrowserStore?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var blockingTask: Task<Bool, Never>?
    @ObservationIgnored private var navigationTask: Task<Void, Never>?
    @ObservationIgnored private var pendingNavigation: (@MainActor (BrowserPage) -> Void)?
    @ObservationIgnored private let siteSearchDiscovery = BrowserSiteSearchDiscovery()
    @ObservationIgnored private(set) var isRetired = false
    @ObservationIgnored var refreshingPageState = false

    // MARK: - Initializers

    init(
        id: UUID, spaceID: UUID, configuration: WKWebViewConfiguration, owner: BrowserStore,
        showsLoadingBackground: Bool = true
    ) {
        self.id = id
        self.spaceID = spaceID
        self.owner = owner
        loading = BrowserPageLoading(showsBackground: showsLoadingBackground)
        contentBlocker = owner.contentBlocker(for: spaceID)
        configuration.webExtensionController = contentBlocker.controller
        // Popup configurations share process/data stores with their opener, but handlers belong to one document host.
        configuration.userContentController = WKUserContentController()
        contentBlocker.register(configuration.userContentController)
        BrowserWebKitDefaults.apply(to: configuration.preferences)
        configuration.applicationNameForUserAgent = BrowserPlatformUserAgent.applicationName
        BrowserDesktopPictureInPictureAccess.enable(in: configuration.preferences)
        BrowserPictureInPictureContentBridge.shared.install(in: configuration.userContentController)
        let webView = BrowserNativeWebView(frame: .zero, configuration: configuration)
        self.webView = webView
        documentActivity = BrowserDocumentActivity(webView: webView)
        super.init()
        webView.page = self
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.isInspectable = true
        observations = [
            webView.observe(\.url, options: [.initial, .new]) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.synchronize() }
            },
            webView.observe(\.title, options: [.initial, .new]) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.synchronize() }
            },
            webView.observe(\.isLoading, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.synchronize() }
            },
            webView.observe(\.canGoBack, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.synchronize() }
            },
            webView.observe(\.canGoForward, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.synchronize() }
            },
        ]
        pictureInPicture = BrowserPictureInPicturePageController(webView: webView)
        pictureInPicture?.residencyProtectionChanged = { [weak self] in
            guard let self else { return }
            hasPictureInPicture = pictureInPicture?.isPictureInPictureActive == true
        }
        siteController = BrowserSiteController(page: self)
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: Self.mediaActionScript,
                injectionTime: .atDocumentStart, forMainFrameOnly: false))
        applyContentBlocking()
    }

    // MARK: - Actions - Browsing

    func load(_ url: URL, restoring interactionState: Data? = nil) {
        guard !isRetired else { return }
        failure = nil
        pendingNavigationURL = url
        self.url = url
        owner?.pageChanged(self)
        afterContentBlocking { page in
            let webView = page.webView
            if let interactionState {
                webView.interactionState = interactionState
                if let item = webView.backForwardList.currentItem, BrowserURLs.same(item.url, url) { return }
            }
            if url.isFileURL {
                webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
            } else {
                webView.load(URLRequest(url: url))
            }
        }
    }

    func reloadAfterContentBlocking() {
        afterContentBlocking(pendingNavigation ?? { $0.webView.reload() })
    }

    func stopLoading() {
        loading.stop()
        webView.stopLoading()
    }

    private func afterContentBlocking(_ action: @escaping @MainActor (BrowserPage) -> Void) {
        guard !isRetired else { return }
        navigationTask?.cancel()
        pendingNavigation = action
        let blocking = blockingTask
        waitsForContentBlocking = blocking != nil
        navigationTask = Task { [weak self] in
            let ready = await blocking?.value ?? true
            guard !Task.isCancelled, let self, !isRetired else { return }
            waitsForContentBlocking = false
            navigationTask = nil
            guard ready else { return }
            pendingNavigation = nil
            failure = nil
            action(self)
        }
    }

    func applyContentBlocking() {
        guard !isRetired else { return }
        blockingTask?.cancel()
        let enabled = owner?.spacePreferences(spaceID).blocksContent == true
        blockingTask = Task { [weak self, contentBlocker] in
            do {
                try await contentBlocker.setEnabled(enabled)
                return true
            } catch {
                if !Task.isCancelled {
                    self?.failure = "Content blocking could not load: " + error.localizedDescription
                }
                return false
            }
        }
    }

    func invalidate() {
        guard !isRetired else { return }
        contentBlocker.controller.didCloseTab(self, windowIsClosing: false)
        isRetired = true
        loading.invalidate()
        navigationTask?.cancel()
        navigationTask = nil
        pendingNavigation = nil
        blockingTask?.cancel()
        blockingTask = nil
        webView.evaluateJavaScript("globalThis.__browserFaviconFetch?.abort()", in: nil, in: .defaultClient) { _ in }
        observations.removeAll()
        // UI transitions and pending callbacks can retain a retired page.
        // End playback now rather than waiting for its web view to deallocate.
        webView.setAllMediaPlaybackSuspended(true, completionHandler: {})
        webView.stopLoading()
        webView.removeFromSuperview()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        pictureInPicture?.invalidate()
        documentActivity.invalidate()
        siteController?.invalidate()
        for scope in uploadScopes { scope.stopAccessingSecurityScopedResource() }
        uploadScopes.removeAll()
        finishClose(false)
        owner = nil
    }

    private func synchronize() {
        guard !isRetired else { return }
        title = String((webView.title ?? "").prefix(2048))
        url = pendingNavigationURL ?? webView.url
        isLoading = webView.isLoading
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        if owner?.pages[id] === self {
            contentBlocker.controller.didChangeTabProperties([.URL, .title, .loading], for: self)
        }
        owner?.pageChanged(self)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        guard !isRetired else { return }
        loading.started(navigation)
        failure = nil
        documentActivity.navigationStarted()
        siteController?.navigationStarted()
        isReaderMode = false
        documentRevision &+= 1
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        loading.committed(navigation, in: webView)
        pendingNavigationURL = nil
        synchronize()
        pictureInPicture?.navigationDidCommit()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loading.finished(navigation)
        pendingNavigationURL = nil
        synchronize()
        owner?.pageFinished(self)
        siteSearchDiscovery.finished(self)
        checkpointNativeState()
        Task { [weak self] in
            await self?.restoreDocumentState()
            await self?.refreshReaderAvailability()
        }
        Task { [weak self] in
            await self?.refreshPageState()
            self?.captureMirror()
        }
        captureFavicon()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loading.failed(navigation, committed: false)
        handleNavigationFailure(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loading.failed(navigation, committed: true)
        handleNavigationFailure(error)
    }

    private func handleNavigationFailure(_ error: Error) {
        let value = error as NSError
        if value.code == NSURLErrorCancelled || (value.domain == "WebKitErrorDomain" && value.code == 102) {
            pendingNavigationURL = nil
            synchronize()
            return
        }
        failure = error.localizedDescription
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        loading.stop()
        failure = "This page stopped. Reload to continue."
        isPlaying = false
        pictureInPicture?.invalidate()
    }

    func webView(
        _ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = action.request.url else {
            decisionHandler(.cancel)
            return
        }
        let allowed = ["http", "https", "file", "about", "data", "blob", "javascript"]
        if !allowed.contains(url.scheme?.lowercased() ?? "") {
            decisionHandler(.cancel)
            if action.navigationType == .linkActivated || (scriptMayClose && action.targetFrame?.isMainFrame == true) {
                Task {
                    let alert = NSAlert()
                    alert.messageText = "Open an external application?"
                    alert.informativeText = "This link uses \(url.scheme ?? "an external") and will leave Browser."
                    alert.addButton(withTitle: "Cancel")
                    alert.addButton(withTitle: "Open")
                    if await BrowserDialogs.ask(alert, in: webView.window) == .alertSecondButtonReturn {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        } else if url.isFileURL && action.sourceFrame.request.url?.isFileURL != true && self.url?.isFileURL != true {
            decisionHandler(.cancel)
        } else {
            if action.targetFrame?.isMainFrame == true && url.scheme != "javascript" {
                siteSearchDiscovery.requested(action, url: url)
                pendingNavigationURL = url
                self.url = url
                owner?.pageChanged(self)
            }
            decisionHandler(action.shouldPerformDownload ? .download : .allow)
        }
    }

    func webView(
        _ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void
    ) {
        siteSearchDiscovery.received(response)
        decisionHandler(response.canShowMIMEType ? .allow : .download)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        receiveDownload(download)
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        if navigationResponse.isForMainFrame { loading.stop() }
        receiveDownload(download)
    }

    private func receiveDownload(_ download: WKDownload) {
        pendingNavigationURL = nil
        failure = nil
        synchronize()
        guard let owner else {
            download.cancel { _ in }
            return
        }
        owner.beginDownload(download, spaceID: spaceID)
    }

    func webView(
        _ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @MainActor @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let generation = documentRevision
        Task {
            let result = await BrowserAuthentication.answer(challenge, in: webView.window ?? owner?.window)
            guard generation == documentRevision, owner != nil else {
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }
            completionHandler(result.0, result.1)
        }
    }

    // MARK: - Actions - Native website UI

    func webView(
        _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard let owner else { return nil }
        if navigationAction.request.url?.isFileURL == true
            && navigationAction.sourceFrame.request.url?.isFileURL != true
        {
            return nil
        }
        if let origin = BrowserSiteController.origin(navigationAction.sourceFrame.securityOrigin),
            owner.permission(.popups, origin: origin, spaceID: spaceID) == .deny
        {
            return nil
        }
        return owner.openPopup(configuration: configuration, url: navigationAction.request.url, spaceID: spaceID)
    }

    func webView(
        _ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable () -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = frame.request.url?.host ?? "Website"
        alert.informativeText = String(message.prefix(4_000))
        alert.addButton(withTitle: "OK")
        present(alert) { _ in completionHandler() }
    }

    func webView(
        _ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = frame.request.url?.host ?? "Website"
        alert.informativeText = String(message.prefix(4_000))
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        present(alert) { completionHandler($0 == .alertFirstButtonReturn) }
    }

    func webView(
        _ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
        initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable (String?) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = frame.request.url?.host ?? "Website"
        alert.informativeText = String(prompt.prefix(4_000))
        let field = NSTextField(string: defaultText ?? "")
        field.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        present(alert) { completionHandler($0 == .alertFirstButtonReturn ? field.stringValue : nil) }
    }

    func webView(
        _ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable ([URL]?) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.canChooseFiles = true
        if let window = webView.window {
            panel.beginSheetModal(for: window) {
                if $0 == .OK {
                    for url in panel.urls {
                        if url.startAccessingSecurityScopedResource() { self.uploadScopes.append(url) }
                    }
                    completionHandler(panel.urls)
                } else {
                    completionHandler(nil)
                }
            }
        } else {
            completionHandler(nil)
        }
    }

    func webView(
        _ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
        decisionHandler: @escaping @MainActor @Sendable (WKPermissionDecision) -> Void
    ) {
        Task { [weak self] in
            guard let self, let siteController else {
                decisionHandler(.deny)
                return
            }
            let generation = documentRevision
            guard webView === self.webView, frame.webView === webView,
                let name = BrowserSiteController.origin(origin)
            else {
                decisionHandler(.deny)
                return
            }
            let kinds: [BrowserSitePermission.Kind] =
                type == .camera ? [.camera] : type == .microphone ? [.microphone] : [.camera, .microphone]
            for kind in kinds {
                guard await siteController.decide(kind, origin: origin, frame: frame) else {
                    decisionHandler(.deny)
                    return
                }
            }
            guard generation == documentRevision,
                kinds.allSatisfy({ owner?.permission($0, origin: name, spaceID: spaceID) == .allow })
            else {
                decisionHandler(.deny)
                return
            }
            siteController.recordCapture(kinds, origin: name)
            decisionHandler(.grant)
        }
    }

    private func present(
        _ alert: NSAlert, completion: @escaping @MainActor @Sendable (NSApplication.ModalResponse) -> Void
    ) {
        guard let window = webView.window ?? NSApp.mainWindow else {
            completion(.abort)
            return
        }
        alert.beginSheetModal(for: window, completionHandler: completion)
    }

    // MARK: - Actions - Page images

    func captureMirror() {
        guard isSharedAcrossWindows, webView.bounds.width > 0 else { return }
        webView.takeSnapshot(with: nil) { [weak self] image, _ in self?.mirrorImage = image }
    }

    private func captureFavicon() {
        guard !isRetired else { return }
        let script = #"""
            const link = document.querySelector('link[rel~="icon"]');
            const url = new URL(link?.href || '/favicon.ico', location.href);
            if(!['https:', 'http:'].includes(url.protocol)) return null;
            globalThis.__browserFaviconFetch?.abort();
            const controller = new AbortController();
            globalThis.__browserFaviconFetch = controller;
            const timeout = setTimeout(() => controller.abort(), 12000);
            try {
              const response = await fetch(url, {credentials:'same-origin', signal:controller.signal});
              if(!response.ok) return null;
              const blob = await response.blob();
              if(blob.size > 32768) return null;
              return await new Promise(resolve => { const reader = new FileReader();
                reader.onload = () => resolve(reader.result); reader.onerror = () => resolve(null);
                reader.readAsDataURL(blob); });
            } catch { return null; }
            finally {
              clearTimeout(timeout);
              if(globalThis.__browserFaviconFetch === controller) delete globalThis.__browserFaviconFetch;
            }
            """#
        let document = documentRevision
        webView.callAsyncJavaScript(script, arguments: [:], in: nil, in: .defaultClient) { [weak self] result in
            guard let self, !isRetired, document == documentRevision,
                case .success(let value) = result, let dataURL = value as? String,
                let comma = dataURL.firstIndex(of: ","),
                let data = Data(base64Encoded: String(dataURL[dataURL.index(after: comma)...])),
                NSImage(data: data) != nil
            else { return }
            favicon = data
            owner?.pageChanged(self)
        }
    }
}
